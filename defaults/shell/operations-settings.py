#!/usr/bin/env python3
"""Capability-aware Settings dispatcher and durable, detached job worker.

Requests travel over stdin, never command arguments or persisted job records.
Only explicitly registered provider actions execute. Status never starts work.
"""
import datetime
import importlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import uuid
from settings_support import atomic, check_revision, digest, locked
from settings_operations import notice

PROVIDERS = {
    'vpn': 'settings_network', 'sharing': 'settings_network',
    'datetime': 'settings_devices', 'printers': 'settings_devices',
    'disk-usage': 'settings_storage', 'drives': 'settings_storage', 'disk-health': 'settings_storage',
    'installed': 'settings_apps', 'permissions': 'settings_apps', 'updates': 'settings_apps',
    'firmware': 'settings_devices', 'assistive': 'settings_session', 'accounts': 'settings_session',
    'backup': 'settings_backup', 'restore': 'settings_backup', 'snapshots': 'settings_recovery',
    'hibernate': 'settings_recovery',
}
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'blankweave/settings-jobs'


def provider(domain):
    if domain not in PROVIDERS: raise ValueError('Unknown Settings provider.')
    return importlib.import_module(PROVIDERS[domain])


def identity(pid):
    try:
        # The command name may contain spaces or closing parentheses.
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        if fields[0] == 'Z': return None
        return Path('/proc/sys/kernel/random/boot_id').read_text().strip() + ':' + fields[19]
    except (OSError, IndexError): return None


def job_path(domain):
    if domain not in PROVIDERS: raise ValueError('Unknown Settings provider.')
    return STATE / (domain + '.json')


def read_job(domain):
    path = job_path(domain)
    job = json.loads(path.read_text()) if path.exists() else None
    if job and job['phase'] in ('starting', 'running') and identity(job['pid']) != job['process']:
        job = {**job, 'phase': 'interrupted', 'message': 'The worker stopped before reporting completion. Refresh state before retrying.', 'cancellable': False}
    return job


def revision(data):
    return digest({'identity': data.get('identity'), 'actions': data.get('actions')})


def status(domain):
    try:
        data = provider(domain).status(domain)
    except Exception as error:
        data = dict(message='Provider unavailable: ' + str(error)[:2000], details=[], actions=[], identity=None, notices=[notice('service-unavailable', 'Could not read current state', 'Refresh to try again. If this continues, check the service or connection named in the error below.')])
    data['revision'] = revision(data)
    data['job'] = read_job(domain)
    data['writable'] = not data['job'] or data['job']['phase'] not in ('starting', 'running')
    return data


def start(domain, request):
    with locked('operations-' + domain):
        data = status(domain)
        check_revision(request, data)
        if not data['writable']: raise ValueError('An operation is already running.')
        operation = next((a for a in data['actions'] if a['key'] == request.get('action')), None)
        if not operation: raise ValueError('This operation is unavailable. Refresh and try again.')
        if operation['confirm'] and request.get('confirmed') is not True:
            raise ValueError('Review and confirm this operation first.')
        # Restrict fields to the current provider schema before spawning.
        keys = {f['key'] for f in operation['fields']} | {'action', 'revision', 'confirmed'}
        if set(request) - keys: raise ValueError('Unexpected operation fields.')
        token = uuid.uuid4().hex
        child = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), domain, 'worker', token],
                                 stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True, text=True)
        job = dict(id=token, pid=child.pid, process=identity(child.pid), phase='starting',
                   label=operation['label'], cancellable=operation['cancellable'], message='',
                   started=datetime.datetime.now().astimezone().isoformat(timespec='seconds'))
        STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
        atomic(job_path(domain), json.dumps(job))
        child.stdin.write(json.dumps(request)); child.stdin.close()
        child.settings_job_id = token
        return child


def worker(domain, token, request):
    # Parent releases the short reservation lock after writing the request.
    # The worker owns a separate lifetime lock; status reads never wait on it.
    with locked('worker-' + domain):
        job = read_job(domain)
        if not job or job['id'] != token: raise ValueError('Job reservation expired.')
        job.update(phase='running')
        atomic(job_path(domain), json.dumps(job))
        try:
            # Revalidate resource identities immediately before mutation.
            current = provider(domain).status(domain)
            check_revision(request, {'revision': revision(current)})
            output = provider(domain).apply(domain, request)
            text = str(output or 'Completed. Refresh to see current state.')
            job.update(phase='completed', message=text[:16384] + ('\n[Report truncated; narrow the operation to see more.]' if len(text) > 16384 else ''))
        except Exception as error:
            job.update(phase='failed', message=str(error)[:4000])
        job['cancellable'] = False
        job['finished'] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
        atomic(job_path(domain), json.dumps(job))


def cancel(domain, request):
    with locked('operations-' + domain):
        job = read_job(domain)
        if not job or job['id'] != request.get('id') or not job['cancellable'] or job['phase'] not in ('starting', 'running'):
            raise ValueError('This job cannot be cancelled.')
        if identity(job['pid']) != job['process']: raise ValueError('The worker has already stopped.')
        os.killpg(job['pid'], signal.SIGTERM)
        job.update(phase='cancelled', cancellable=False, message='Cancelled. Review current state before retrying.',
                   finished=datetime.datetime.now().astimezone().isoformat(timespec='seconds'))
        atomic(job_path(domain), json.dumps(job))


def main():
    try:
        if sys.argv[1:] == ['jobs']:
            reports = []
            for domain in PROVIDERS:
                try:
                    job = read_job(domain)
                    if job: reports.append(dict(job, domain=domain))
                except (OSError, ValueError, KeyError, TypeError):
                    continue  # One damaged report must not hide other running jobs.
            print(json.dumps(reports))
            return 0
        domain, command = sys.argv[1:3]
        provider(domain)
        if command == 'status': print(json.dumps(status(domain)))
        elif command == 'apply':
            request = json.load(sys.stdin)
            if request.get('action') == 'cancel-job': cancel(domain, request)
            else:
                child = start(domain, request)
                print(json.dumps({'jobId': child.settings_job_id}))
        elif command == 'worker': worker(domain, sys.argv[3], json.load(sys.stdin))
        elif command == 'scheduled' and domain == 'backup':
            data = status(domain)
            request = {'action': 'backup', 'revision': data['revision'], 'confirmed': True}
            child = start(domain, request)
            child.wait()
            job = read_job(domain)
            if not job or job['phase'] != 'completed':
                import shutil
                if shutil.which('dunstify'):
                    subprocess.run(['dunstify', '-a', 'Blankweave Backup', '-u', 'critical', 'Scheduled backup failed', 'Open Storage & Backup in Settings to review the failure.'], timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                raise ValueError((job or {}).get('message', 'Scheduled backup did not complete.'))
        else: raise ValueError('Usage: domain status|apply')
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr); return 1
    return 0


if __name__ == '__main__': sys.exit(main())
