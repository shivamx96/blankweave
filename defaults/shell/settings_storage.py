"""Storage inspection and UDisks operations; never partitions or formats disks."""
import json
import os
from pathlib import Path
import shutil
import subprocess
from settings_operations import action, choice, field, installed, path_value, privileged, require, run, select, state


def blocks():
    data = json.loads(run(['lsblk', '--json', '--bytes', '--output', 'PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS,RM,TRAN,UUID,MAJ:MIN']))
    def flatten(rows):
        for row in rows:
            yield row
            yield from flatten(row.get('children', []))
    return list(flatten(data['blockdevices']))


def removable(rows):
    paths = set()
    def visit(row, external=False):
        external = external or row.get('rm') is True or row.get('tran') in ('usb', 'firewire')
        if external: paths.add(row['path'])
        for child in row.get('children', []): visit(child, external)
    for row in rows: visit(row)
    return [r for r in rows if r['path'] in paths]


def stable(rows):
    result = []
    for row in rows:
        diskseq = Path('/sys/dev/block') / row['maj:min'] / 'diskseq'
        result.append([row['path'], row['maj:min'], row.get('uuid'), row['size'], row.get('mountpoints'),
                       diskseq.read_text().strip() if diskseq.exists() else ''])
    return result


def health_disks(rows):
    return [row for row in rows if row['type'] == 'disk'
            and '/virtual/' not in str((Path('/sys/dev/block') / row['maj:min']).resolve())]


def thumbnail_cache():
    base = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache'))
    target = base / 'thumbnails'
    if base.is_symlink() or target.is_symlink(): raise ValueError('Thumbnail cache is symlinked; manage it at its source.')
    return target


def status(domain):
    if domain == 'disk-usage':
        usage = shutil.disk_usage(Path.home())
        cache = thumbnail_cache()
        stamp = cache.stat().st_mtime_ns if cache.exists() else None
        return state('Scans run only when requested and stay on one filesystem. Cleanup removes only this user’s generated thumbnail cache.',
                     [f'Home filesystem: {usage.used / 2**30:.1f} GiB used / {usage.total / 2**30:.1f} GiB total; {usage.free / 2**30:.1f} GiB free'],
                     [action('scan', 'Scan directory usage', [field('folder', 'Directory', str(Path.home()))], cancellable=True),
                      action('preview-cleanup', 'Review thumbnail cleanup', cancellable=True)] +
                     ([action('cleanup', 'Clear thumbnail cache', confirm=f'Delete generated thumbnails in {cache}? Applications will recreate them.')] if cache.exists() else []),
                     [str(cache), stamp])
    if not installed('lsblk'): return state('Install util-linux to inspect block devices.')
    rows = blocks()
    if domain == 'disk-health':
        disks = health_disks(rows)
        options = [choice(r['path'], f'{r["path"]} ({r["size"] / 2**30:.1f} GiB)') for r in disks]
        actions = []
        if installed('smartctl') and options:
            target = field('device', 'Drive', options[0]['value'], options)
            actions = [action('health', 'Read drive health', [target]),
                       action('self-test', 'Start short self-test', [target], 'Start a drive self-test. Read health again later to see the result.')]
        return state('Health telemetry requires smartmontools and administrator authorization. Unsupported telemetry does not mean a drive is healthy.', [p['label'] for p in options], actions, stable(disks))
    rows = removable(rows)
    options = [choice(r['path'], r['path'] + ' · ' + str(r.get('fstype') or r['type']) + ' · ' + ', '.join(filter(None, r.get('mountpoints', [])))) for r in rows]
    actions = []
    if installed('udisksctl') and options:
        target = field('device', 'Removable device', options[0]['value'], options)
        actions = [action('mount', 'Mount filesystem', [target]), action('unmount', 'Unmount filesystem', [target]),
                   action('unlock', 'Unlock encrypted volume', [target, field('password', 'Passphrase', secret=True)]),
                   action('lock', 'Lock encrypted volume', [target]),
                   action('eject', 'Safely power off drive', [target], 'Unmount every filesystem on this drive before powering it off.')]
    return state('Only removable/USB storage is offered here. UDisks handles authorization and busy-device checks. Install udisks2 if controls are unavailable.', [p['label'] for p in options] or ['No removable storage found.'], actions, stable(rows))


def apply(domain, request):
    command = request['action']
    if domain == 'disk-usage':
        if command == 'scan':
            folder = path_value(request, 'folder', directory=True)
            result = subprocess.run(['du', '-x', '-h', '--max-depth=1', '--', str(folder)], capture_output=True, text=True, timeout=3600)
            if result.returncode not in (0, 1): raise ValueError('Directory scan failed.')
            return result.stdout[-14000:] + ('\nSome paths could not be read; totals are incomplete.\n' + result.stderr[-2000:] if result.returncode else '')
        cache = thumbnail_cache()
        if command == 'preview-cleanup':
            if not cache.exists(): return 'No thumbnail cache exists.'
            return run(['du', '-sh', '--', str(cache)]) + '\nOnly generated thumbnails will be removed.'
        if command == 'cleanup':
            if cache.exists(): shutil.rmtree(cache)
            return 'Thumbnail cache cleared.'
    if domain == 'disk-health':
        device = select(request, 'device', [r['path'] for r in health_disks(blocks())])
        if command in ('health', 'self-test'): return privileged('disk-' + command, device=device)
    if domain == 'drives':
        rows = removable(blocks())
        device = select(request, 'device', [r['path'] for r in rows])
        row = next(r for r in rows if r['path'] == device)
        if command in ('mount', 'unmount'):
            if row.get('fstype') in (None, '', 'crypto_LUKS', 'swap'): raise ValueError('Select a regular filesystem.')
            return run(['udisksctl', command, '--block-device', device], timeout=120)
        if command == 'unlock':
            if row.get('fstype') != 'crypto_LUKS': raise ValueError('Select an encrypted volume.')
            password = require(request, 'password')
            return run(['udisksctl', 'unlock', '--block-device', device, '--key-file', '/dev/stdin'], input=password, timeout=120)
        if command == 'lock':
            if row.get('fstype') != 'crypto_LUKS': raise ValueError('Select the encrypted backing volume.')
            return run(['udisksctl', 'lock', '--block-device', device], timeout=120)
        if command == 'eject':
            if row['type'] != 'disk': raise ValueError('Select the whole drive to power off.')
            def mounted(r): return any(r.get('mountpoints') or []) or any(mounted(c) for c in r.get('children', []))
            if mounted(row): raise ValueError('Unmount all filesystems on this drive first.')
            return run(['udisksctl', 'power-off', '--block-device', device], timeout=120)
    raise ValueError('Unknown storage operation.')
