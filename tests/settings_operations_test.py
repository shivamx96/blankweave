#!/usr/bin/env python3
"""All system mutations are mocked or run against isolated fixture providers."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'defaults/shell'))
import settings_operations as common
import settings_apps as apps
import settings_backup as backup
import settings_devices as devices
import settings_network as network
import settings_recovery as recovery
import settings_session as session
import settings_storage as storage


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


system = module('system_settings_root', ROOT / 'scripts/settings-system.py')


class Validation(unittest.TestCase):
    def test_field_validation(self):
        for value in ('', '\n', 'bad\0value', 2, None):
            with self.subTest(value=value), self.assertRaises(ValueError): common.require({'name': value}, 'name')
        self.assertEqual(common.require({'name': 'valid name'}, 'name'), 'valid name')

    def test_selection_cannot_retarget(self):
        with self.assertRaises(ValueError): common.select({'id': 'removed'}, 'id', ['new'])

    def test_privileged_request_uses_stdin(self):
        with patch.object(common, 'run', return_value='ok') as run:
            common.privileged('account-password', password='sensitive')
        self.assertNotIn('sensitive', str(run.call_args.args))
        self.assertEqual(json.loads(run.call_args.kwargs['input'])['password'], 'sensitive')

    def test_unknown_root_operation(self):
        with patch.object(system, 'run') as run:
            with self.assertRaises(ValueError): system.execute('shell', {'command': 'touch /root/a'}, 1000)
        run.assert_not_called()

    def test_root_rejects_extra_fields_and_option_injection(self):
        for command, data in [('printer-remove', {'name': '-x'}), ('printer-remove', {'name': 'okay', 'extra': 'x'}),
                              ('snapshot-delete', {'number': '0'}), ('snapshot-delete', {'number': '--all'}),
                              ('hibernate-policy', {'enabled': 'yes\nAllowSuspend=no'})]:
            with self.subTest(command=command), patch.object(system, 'run') as run:
                with self.assertRaises(ValueError): system.execute(command, data, 1000)
                run.assert_not_called()

    def test_root_package_plan_changed(self):
        with patch.object(system, 'run', return_value='example 2') as run:
            with self.assertRaisesRegex(ValueError, 'changed'):
                system.execute('package', {'kind': 'install', 'package': 'example', 'packages': ['example 1']}, 1000)
            self.assertEqual(run.call_count, 1)

    def test_root_protects_core_package(self):
        with patch.object(system, 'run', return_value='pacman 7'), patch.object(Path, 'read_text', return_value='hyprland\n'):
            with self.assertRaisesRegex(ValueError, 'required'):
                system.execute('package', {'kind': 'remove', 'package': 'pacman', 'packages': ['pacman 7']}, 1000)

    def test_root_password_stdin_and_account_guard(self):
        with patch.object(system, 'local_account'), patch.object(system, 'run') as run:
            system.execute('account-password', {'name': 'alice', 'password': 'private'}, 1000)
            self.assertEqual(run.call_args.kwargs['input'], 'alice:private\n')
            self.assertNotIn('private', str(run.call_args.args))
        with patch.object(system, 'local_account', return_value=Mock(pw_uid=1000)):
            with self.assertRaisesRegex(ValueError, 'current'): system.protect_administrator('alice', 1000)

    def test_last_unlocked_admin_protected(self):
        with patch.object(system, 'local_account', return_value=Mock(pw_uid=1001)), patch.object(system.grp, 'getgrnam', return_value=Mock(gr_mem=['alice', 'bob'])), patch.object(Path, 'read_text', return_value='alice:$hash:\nbob:!locked:\n'):
            with self.assertRaisesRegex(ValueError, 'usable'): system.protect_administrator('alice', 1000)

    def test_missing_providers_have_no_fake_operations(self):
        for provider, domain in [(apps, 'installed'), (apps, 'permissions'), (backup, 'backup'), (devices, 'firmware'), (devices, 'datetime'), (recovery, 'snapshots')]:
            with self.subTest(domain=domain), patch.object(provider, 'installed', return_value=False):
                value = provider.status(domain)
                self.assertFalse(value['actions']); self.assertTrue(value['notices'])
                self.assertTrue(value['notices'][0]['nextStep'])


class CapabilityGuidance(unittest.TestCase):
    def test_drives_distinguish_missing_software_and_missing_devices(self):
        with patch.object(storage, 'blocks', return_value=[]), patch.object(storage, 'installed', return_value=True):
            value = storage.status('drives')
            self.assertEqual([n['kind'] for n in value['notices']], ['no-device'])
            self.assertNotIn('Install', value['message'])
            self.assertFalse(value['actions'])
        with patch.object(storage, 'blocks', return_value=[]), patch.object(storage, 'installed', side_effect=lambda command: command != 'udisksctl'):
            self.assertEqual([n['kind'] for n in storage.status('drives')['notices']], ['missing-software', 'no-device'])

    def test_restore_without_configuration_links_to_backup(self):
        with patch.object(backup, 'installed', return_value=True), patch.object(backup, 'config', return_value=None):
            value = backup.status('restore')
            self.assertFalse(value['actions'])
            self.assertEqual(value['notices'][0]['target'], 'backup')
            self.assertEqual(value['notices'][0]['kind'], 'not-configured')
            self.assertIn('configure', backup.status('backup')['actions'][0]['key'])

    def test_backup_lists_only_missing_dependencies(self):
        with patch.object(backup, 'installed', side_effect=lambda *commands: 'secret-tool' not in commands):
            message = backup.status('backup')['notices'][0]['nextStep']
            self.assertIn('libsecret', message)
            self.assertNotIn('restic', message)

    def test_empty_permissions_and_user_installation_scope(self):
        with patch.object(apps, 'installed', return_value=True), patch.object(apps, 'run', return_value='') as run:
            value = apps.status('permissions')
            self.assertEqual(value['notices'][0]['target'], 'installed')
            run.assert_called_once_with(['flatpak', '--user', 'list', '--app', '--columns=application'])

    def test_snapshot_guidance_matches_filesystem(self):
        with patch.object(recovery, 'installed', return_value=True), patch.object(recovery, 'run', return_value='ext4'), patch.object(Path, 'exists', return_value=False):
            value = recovery.status('snapshots')
            self.assertEqual(value['notices'][0]['kind'], 'unsupported')
            self.assertEqual(value['notices'][0]['target'], 'backup')
            self.assertFalse(value['actions'])
        with patch.object(recovery, 'installed', return_value=True), patch.object(recovery, 'run', return_value='btrfs'), patch.object(Path, 'exists', return_value=False):
            value = recovery.status('snapshots')
            self.assertEqual(value['notices'][0]['kind'], 'not-configured')
            self.assertEqual(value['actions'][0]['key'], 'setup')

    def test_firmware_no_devices_does_not_claim_up_to_date(self):
        with patch.object(devices, 'installed', return_value=True), patch.object(devices, 'devices', return_value=[]):
            value = devices.status('firmware')
            self.assertEqual(value['notices'][0]['kind'], 'no-device')
            self.assertIn('does not mean', value['notices'][0]['nextStep'])

    def test_stopped_print_service_is_not_a_missing_package(self):
        with patch.object(devices, 'installed', return_value=True), patch.object(devices, 'printers', return_value=[]), patch.object(devices, 'run', return_value='scheduler is not running'):
            self.assertEqual(devices.status('printers')['notices'][0]['kind'], 'service-unavailable')

    def test_no_vpn_profiles_keeps_import_available(self):
        with patch.object(network, 'installed', side_effect=lambda command: command == 'nmcli'), patch.object(network, 'profiles', return_value=[]), patch.object(network, 'run', return_value=''):
            value = network.status('vpn')
            self.assertEqual(value['notices'][0]['kind'], 'not-configured')
            self.assertEqual(value['actions'][0]['key'], 'import')
            self.assertNotIn('networkmanager', str(value['notices']))

    def test_zram_only_hibernation_explains_missing_disk_swap(self):
        def read(path):
            return {'/sys/power/state':'freeze mem disk', '/sys/power/resume':'0:0',
                    '/proc/swaps':'Filename Type Size Used Priority\n/dev/zram0 partition 4194304 0 100\n'}.get(str(path))
        with patch.object(recovery, 'can_hibernate', return_value='na'), patch.object(recovery, 'read', side_effect=read), patch.object(Path, 'exists', return_value=False):
            value = recovery.status('hibernate')
            self.assertIn('disk-backed swap', value['notices'][0]['title'])
            self.assertNotIn('hibernate', [a['key'] for a in value['actions']])


class Providers(unittest.TestCase):
    def test_datetime_revalidates_timezone(self):
        with patch.object(devices, 'run', return_value='UTC\nAsia/Kolkata') as run:
            with self.assertRaises(ValueError): devices.apply('datetime', {'action': 'timezone', 'zone': 'bad'})
            self.assertEqual(run.call_count, 1)

    def test_manual_time_requires_ntp_off(self):
        with patch.object(devices, 'properties', return_value={'NTP': 'yes'}), patch.object(devices, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'automatic'): devices.apply('datetime', {'action': 'time', 'time': '2026-10-18 12:30:00'})
            run.assert_not_called()

    def test_printer_uri_rejects_credentials(self):
        with patch.object(devices, 'privileged') as privileged:
            with self.assertRaises(ValueError): devices.apply('printers', {'action': 'add', 'name': 'Printer', 'uri': 'ipp://user:secret@host/print'})
            privileged.assert_not_called()

    def test_firmware_revalidates_target(self):
        with patch.object(devices, 'devices', return_value=[{'DeviceId': 'new'}]), patch.object(devices, 'run') as run:
            with self.assertRaises(ValueError): devices.apply('firmware', {'action': 'update', 'device': 'old'})
            run.assert_not_called()

    def test_vpn_deleted_profile_cannot_activate(self):
        with patch.object(network, 'profiles', return_value=[]):
            with self.assertRaises(ValueError): network.apply('vpn', {'action': 'connect', 'uuid': 'removed'})

    def test_sharing_restricts_home_and_guest_access(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(Path, 'home', return_value=Path(tmp)), patch.object(network, 'run') as run:
            network.sharing_apply({'action': 'share', 'name': 'test', 'folder': tmp})
            self.assertIn('guest_ok=n', run.call_args.args[0])
            with self.assertRaises(ValueError): network.sharing_apply({'action': 'share', 'name': 'test', 'folder': '/'})

    def test_removable_children_inherit_usb(self):
        child = {'path': '/dev/sdz1', 'type': 'part', 'rm': False, 'tran': None}
        disk = {'path': '/dev/sdz', 'type': 'disk', 'rm': False, 'tran': 'usb', 'children': [child]}
        internal = {'path': '/dev/nvme0n1', 'tran': 'nvme', 'rm': False}
        self.assertEqual(storage.removable([disk, child, internal]), [disk, child])

    def test_busy_drive_cannot_power_off(self):
        disk = {'path': '/dev/sdz', 'type': 'disk', 'rm': True, 'children': [{'mountpoints': ['/media/data']}]}
        with patch.object(storage, 'blocks', return_value=[disk]), patch.object(storage, 'removable', return_value=[disk]), patch.object(storage, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'Unmount'): storage.apply('drives', {'action': 'eject', 'device': '/dev/sdz'})
            run.assert_not_called()

    def test_cache_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'XDG_CACHE_HOME': tmp}):
            (Path(tmp) / 'thumbnails').symlink_to('/tmp')
            with self.assertRaises(ValueError): storage.thumbnail_cache()

    def test_flatpak_permissions_apply_only_to_selected_app(self):
        with patch.object(apps, 'flatpaks', return_value=['org.example.App']), patch.object(apps, 'run', return_value='') as run:
            apps.apply('permissions', {'action': 'revoke', 'app': 'org.example.App', 'scope': 'audio'})
            self.assertEqual(run.call_args_list[0].args[0], ['flatpak', 'override', '--user', '--nosocket=pulseaudio', 'org.example.App'])

    def test_snapshot_setup_rejects_non_btrfs(self):
        with patch.object(system, 'run', return_value='ext4') as run:
            with self.assertRaisesRegex(ValueError, 'Btrfs'): system.execute('snapshot-setup', {}, 1000)
            self.assertEqual(run.call_count, 1)

    def test_backup_configuration_rejects_recursive_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'separate'):
                backup.validate({'repository': tmp + '/repo', 'source': tmp, 'keep': 14, 'schedule': 'off'})

    def test_backup_missing_destination_never_creates_fallback(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'XDG_CONFIG_HOME': tmp}), patch.object(backup, 'config', return_value={'repository': tmp + '/absent', 'source': tmp, 'keep': 14, 'schedule': 'off'}), patch.object(backup, 'restic') as restic:
            with self.assertRaisesRegex(ValueError, 'unavailable'): backup.apply('backup', {'action': 'backup'})
            restic.assert_not_called(); self.assertFalse((Path(tmp) / 'absent').exists())

    def test_restic_secrets_not_in_arguments(self):
        with patch.object(backup.subprocess, 'run', return_value=Mock(returncode=0, stdout='done')) as run:
            backup.restic({'repository': '/backup'}, ['check'])
            self.assertNotIn('RESTIC_PASSWORD=', str(run.call_args))
            self.assertIn('secret-tool lookup', run.call_args.kwargs['env']['RESTIC_PASSWORD_COMMAND'])

    def test_partial_backup_is_failure(self):
        with patch.object(backup.subprocess, 'run', return_value=Mock(returncode=3, stdout='', stderr='unreadable')):
            with self.assertRaisesRegex(ValueError, 'incomplete'): backup.restic({'repository': '/backup'}, ['backup'])

    def test_idle_hibernation_retains_lock_sequence(self):
        idle = module('idle_policy_operations_test', ROOT / 'defaults/shell/idle-policy.py')
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'XDG_CONFIG_HOME': tmp}):
            path = Path(tmp) / 'blankweave/idle-hibernate'; path.parent.mkdir(); path.write_text('yes\n')
            rendered = idle.sleep_action('before_sleep_cmd = loginctl lock-session\non-timeout = systemctl suspend\n')
            self.assertIn('before_sleep_cmd = loginctl lock-session', rendered)
            self.assertIn('settings_recovery.py idle', rendered)
            path.write_text('no\n')
            self.assertEqual(idle.sleep_action('on-timeout = systemctl suspend'), 'on-timeout = systemctl suspend')

    def test_magnifier_failed_readback_restores_preferences(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(session, 'ZOOM', Path(tmp) / 'magnifier.lua'), patch.object(session, 'run', side_effect=['{"float":1}', '', '{"float":1}', '']) as run:
            with self.assertRaisesRegex(ValueError, 'did not apply'): session.apply('assistive', {'action': 'zoom', 'factor': '2'})
            self.assertFalse(session.ZOOM.exists())
            self.assertIn('zoom_factor = 1', run.call_args.args[0][-1])

    def test_reader_service_enables_toolkit_and_session_start(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(session, 'UNITS', Path(tmp)), patch.object(session, 'installed', return_value=True), patch.object(session, 'run', return_value='active') as run:
            session.apply('assistive', {'action': 'reader', 'enabled': 'yes', 'startup': 'yes'})
            text = (Path(tmp) / 'blankweave-reader.service').read_text()
            self.assertIn('WantedBy=graphical-session.target', text)
            self.assertIn('After=graphical-session-pre.target', text)
            run.assert_any_call(['gsettings', 'set', 'org.gnome.desktop.interface', 'toolkit-accessibility', 'true'])

    def test_unknown_operation_does_not_mutate(self):
        for provider, domain in [(storage, 'disk-usage'), (devices, 'datetime'), (network, 'vpn')]:
            with self.subTest(domain=domain), patch.object(provider, 'run') as run:
                with self.assertRaises((ValueError, KeyError)): provider.apply(domain, {'action': 'invalid'})
                run.assert_not_called()


class BackupConfiguration(unittest.TestCase):
    def test_retention_control_bounds_match_backend_validation(self):
        with patch.object(backup, 'installed', return_value=True), patch.object(backup, 'config', return_value=None):
            fields = backup.status('backup')['actions'][0]['fields']
        retention = next(field for field in fields if field['key'] == 'keep')
        self.assertEqual(retention['inputType'], 'integer')
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'; source.mkdir()
            data = dict(repository=str(Path(tmp) / 'repository'), source=str(source), schedule='off')
            for keep in (retention['minimum'], retention['maximum']):
                backup.validate(dict(data, keep=keep))
            for keep in (retention['minimum'] - 1, retention['maximum'] + 1):
                with self.assertRaises(ValueError): backup.validate(dict(data, keep=keep))

    def test_wrong_replacement_password_preserves_saved_credential(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'source'; source.mkdir()
            repository = root / 'repository'; repository.mkdir(); (repository / 'config').write_text('fixture')
            config = root / 'backup.json'
            original = dict(repository=str(repository), source=str(source), keep=14, schedule='off')
            config.write_text(json.dumps(original))
            request = dict(original, action='configure', keep='14', password='wrong', exclude='')
            with patch.dict(os.environ, {'XDG_CONFIG_HOME': tmp}), patch.object(backup, 'CONFIG', config), patch.object(backup.subprocess, 'run', return_value=Mock(returncode=1)), patch.object(backup, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'preserved'): backup.apply('backup', request)
                run.assert_not_called()
                self.assertEqual(json.loads(config.read_text()), original)

    def test_timer_failure_rolls_back_config_and_units(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'source'; source.mkdir()
            config = root / 'backup.json'; units = root / 'units'; units.mkdir()
            original = dict(repository=str(root / 'repository'), source=str(source), keep=14, schedule='off')
            config.write_text(json.dumps(original))
            service = units / 'blankweave-backup.service'; service.write_text('previous service')
            timer = units / 'blankweave-backup.timer'; timer.write_text('previous timer')
            request = dict(original, action='configure', keep='7', schedule='daily', password='', exclude='')
            calls = []
            def schedule(data):
                calls.append(data)
                if len(calls) == 1:
                    service.write_text('new service'); timer.write_text('new timer')
                    raise ValueError('fixture timer failure')
            with patch.dict(os.environ, {'XDG_CONFIG_HOME': tmp}), patch.object(backup, 'CONFIG', config), patch.object(backup, 'UNITS', units), patch.object(backup, 'schedule', side_effect=schedule), patch.object(backup, 'run'):
                with self.assertRaisesRegex(ValueError, 'fixture'): backup.apply('backup', request)
            self.assertEqual(json.loads(config.read_text()), original)
            self.assertEqual(service.read_text(), 'previous service')
            self.assertEqual(timer.read_text(), 'previous timer')
            self.assertEqual(calls[-1]['schedule'], 'off')


class ResumePreparation(unittest.TestCase):
    def test_commandline_preserves_options_and_rejects_foreign_resume(self):
        self.assertEqual(system.resume_options('quiet root=UUID=root\n', 'resume=UUID=swap'), 'quiet root=UUID=root resume=UUID=swap\n')
        self.assertEqual(system.resume_options('title Linux\noptions quiet\nlinux /vmlinuz-linux\n', 'resume=UUID=swap', True), 'title Linux\noptions quiet resume=UUID=swap\nlinux /vmlinuz-linux\n')
        with self.assertRaises(ValueError): system.resume_options('quiet resume=UUID=other', 'resume=UUID=swap')
        with self.assertRaises(ValueError): system.resume_options('quiet resume_offset=123', 'resume=UUID=swap')

    def fixture(self, root):
        files = {'proc/meminfo': 'MemTotal: 1024 kB\n', 'etc/crypttab.initramfs': 'swap UUID=abcd none luks\n',
                 'etc/mkinitcpio.conf': 'HOOKS=(base systemd sd-encrypt filesystems)\n',
                 'etc/kernel/cmdline': 'root=UUID=root quiet\n',
                 'boot/loader/entries/linux.conf': 'title Linux\nlinux /vmlinuz-linux\noptions root=UUID=root quiet\n'}
        for name, content in files.items():
            path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(content)
        return files

    def paths(self, root, value):
        path = Path(value)
        return path if path.is_relative_to(root) else root / str(path).lstrip('/')

    def runner(self, args):
        if args[0].endswith('swapon'): return json.dumps({'swapdevices': [{'name': '/dev/mapper/swap', 'type': 'partition', 'size': 2097152}]})
        if args[0].endswith('lsblk'): return 'crypt'
        if args[0].endswith('blkid'): return 'abcd-1234'
        if args[0].endswith('bootctl'): return '/boot'
        return ''

    def test_encrypted_swap_preparation_and_revert(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); files = self.fixture(root); record = root / 'record.json'
            with patch.object(system, 'Path', side_effect=lambda value: self.paths(root, value)), patch.object(system, 'HIBERNATE_RECORD', record), patch.object(system, 'run', side_effect=self.runner):
                system.hibernate_prepare('/dev/mapper/swap')
                self.assertEqual(record.stat().st_mode & 0o777, 0o600)
                self.assertIn('resume=UUID=abcd-1234', (root / 'etc/kernel/cmdline').read_text())
                system.hibernate_revert()
                self.assertFalse(record.exists())
                for name, content in files.items(): self.assertEqual((root / name).read_text(), content)

    def test_failed_rebuild_restores_originals(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); files = self.fixture(root); record = root / 'record.json'
            failures = []
            def runner(args):
                if args[0].endswith('mkinitcpio') and not failures:
                    failures.append(True); raise ValueError('fixture build failure')
                return self.runner(args)
            with patch.object(system, 'Path', side_effect=lambda value: self.paths(root, value)), patch.object(system, 'HIBERNATE_RECORD', record), patch.object(system, 'run', side_effect=runner):
                with self.assertRaisesRegex(ValueError, 'fixture'): system.hibernate_prepare('/dev/mapper/swap')
                self.assertFalse(record.exists())
                for name, content in files.items(): self.assertEqual((root / name).read_text(), content)

    def test_plain_swap_rejected_before_boot_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); files = self.fixture(root)
            with patch.object(system, 'Path', side_effect=lambda value: self.paths(root, value)), patch.object(system, 'HIBERNATE_RECORD', root / 'record.json'), patch.object(system, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'encrypted'): system.hibernate_prepare('/dev/sda2')
                run.assert_not_called()
                for name, content in files.items(): self.assertEqual((root / name).read_text(), content)


class BackupRoundTrip(unittest.TestCase):
    def test_encrypted_backup_restore_preserves_content(self):
        binary = os.environ.get('BLANKWEAVE_RESTIC_TEST_BINARY') or shutil.which('restic')
        if not binary: self.skipTest('restic is not installed; CI installs it for the round-trip test')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'source'; source.mkdir()
            (source / 'document.txt').write_text('Blankweave encrypted round trip\n')
            (source / 'excluded.txt').write_text('excluded by policy')
            tools = root / 'bin'; tools.mkdir()
            (tools / 'restic').symlink_to(binary)
            secret = tools / 'secret-tool'
            secret.write_text('#!/bin/sh\nprintf "%s" "test-only-repository-password"\n'); secret.chmod(0o700)
            env = {'PATH': str(tools) + ':' + os.environ['PATH'], 'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_CACHE_HOME': str(root / 'cache')}
            data = {'repository': str(root / 'repository'), 'source': str(source), 'keep': 2, 'schedule': 'off', 'exclude': [str(source / 'excluded.txt')]}
            with patch.dict(os.environ, env), patch.object(backup, 'config', return_value=data):
                backup.apply('backup', {'action': 'init'})
                backup.apply('backup', {'action': 'backup'})
                snapshots = json.loads(backup.restic(data, ['snapshots', '--json']))
                self.assertEqual(len(snapshots), 1)
                result = backup.apply('restore', {'action': 'restore', 'snapshot': snapshots[0]['id'], 'include': '/', 'folder': str(root)})
                restored = next(root.glob('Restored-*')) / str(source).lstrip('/')
                self.assertEqual((restored / 'document.txt').read_bytes(), (source / 'document.txt').read_bytes())
                self.assertFalse((restored / 'excluded.txt').exists())
                self.assertIn('Restored to', result)
                backup.apply('backup', {'action': 'check'})


class Jobs(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.directory = Path(self.temp.name)
        self.env = {**os.environ, 'HOME': self.temp.name, 'XDG_CONFIG_HOME': str(self.directory / 'config'), 'XDG_STATE_HOME': str(self.directory / 'state'), 'PYTHONDONTWRITEBYTECODE': '1'}
        for name in ('operations-settings.py', 'settings_support.py', 'settings_operations.py'):
            shutil.copy(ROOT / 'defaults/shell' / name, self.directory)
        (self.directory / 'settings_network.py').write_text('''import time
from pathlib import Path
def status(domain):
    return dict(message='', details=[], identity='fixture', actions=[dict(key='work', label='Work', fields=[], confirm='Confirm', cancellable=True), dict(key='slow', label='Slow', fields=[], confirm='Confirm', cancellable=True)])
def apply(domain, request):
    time.sleep(5 if request['action'] == 'slow' else 0.15)
    return 'fixture completed'
''')
        self.command = [sys.executable, str(self.directory / 'operations-settings.py'), 'vpn']

    def tearDown(self):
        # Stop any still-running isolated fixture worker before removing files.
        path = self.directory / 'state/blankweave/settings-jobs/vpn.json'
        if path.exists():
            job = json.loads(path.read_text())
            if job['phase'] in ('starting', 'running'):
                self.call('apply', {'action': 'cancel-job', 'id': job['id']})
        self.temp.cleanup()

    def call(self, command, request=None):
        return subprocess.run(self.command + [command], input=json.dumps(request) if request else None, capture_output=True, text=True, env=self.env, timeout=10)

    def status(self):
        result = self.call('status'); self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_job_survives_request_process_and_reports_completion(self):
        before = self.status()
        result = self.call('apply', {'action': 'work', 'revision': before['revision'], 'confirmed': True})
        self.assertEqual(result.returncode, 0, result.stderr)
        for _ in range(50):
            current = self.status()
            if current['job']['phase'] == 'completed': break
            time.sleep(0.02)
        self.assertEqual(current['job']['phase'], 'completed')
        self.assertGreaterEqual(current['job']['finished'], current['job']['started'])
        self.assertEqual(json.loads(result.stdout)['jobId'], current['job']['id'])
        self.assertEqual(current['job']['message'], 'fixture completed')
        self.assertEqual(current['revision'], before['revision'])

    def test_jobs_lists_reports_without_loading_providers_and_skips_corruption(self):
        directory = self.directory / 'state/blankweave/settings-jobs'
        directory.mkdir(parents=True)
        report = dict(id='saved', phase='completed', label='Work', message='Done')
        (directory / 'vpn.json').write_text(json.dumps(report))
        (directory / 'sharing.json').write_text('{broken')
        (self.directory / 'settings_network.py').write_text('raise RuntimeError("must not load provider")')
        result = subprocess.run(self.command[:-1] + ['jobs'], capture_output=True, text=True, env=self.env, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [dict(report, domain='vpn')])

    def test_failed_status_has_service_guidance_without_actions(self):
        (self.directory / 'settings_network.py').write_text('def status(domain):\n    raise ValueError("service offline")\n')
        value = self.status()
        self.assertEqual(value['notices'][0]['kind'], 'service-unavailable')
        self.assertFalse(value['actions'])
        self.assertIn('service offline', value['message'])

    def test_stale_revision_and_missing_confirmation_rejected(self):
        for request in ({'action': 'work', 'revision': 'stale', 'confirmed': True}, {'action': 'work', 'revision': self.status()['revision']}):
            self.assertNotEqual(self.call('apply', request).returncode, 0)
        self.assertIsNone(self.status()['job'])

    def test_one_job_at_a_time_and_cancel(self):
        request = {'action': 'slow', 'revision': self.status()['revision'], 'confirmed': True}
        self.assertEqual(self.call('apply', request).returncode, 0)
        self.assertNotEqual(self.call('apply', request).returncode, 0)
        job = self.status()['job']
        self.assertEqual(self.call('apply', {'action': 'cancel-job', 'id': job['id']}).returncode, 0)
        cancelled = self.status()['job']
        self.assertEqual(cancelled['phase'], 'cancelled')
        self.assertGreaterEqual(cancelled['finished'], cancelled['started'])


if __name__ == '__main__': unittest.main()
