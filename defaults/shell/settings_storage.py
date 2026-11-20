"""Storage inspection and UDisks operations; never partitions or formats disks."""
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import stat
import time
from settings_support import file_refusal
from settings_operations import missing, notice, action, choice, field, installed, path_value, privileged, require, run, select, state


def blocks():
    data = json.loads(run(['lsblk', '--json', '--bytes', '--output', 'PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS,RM,TRAN,UUID,MAJ:MIN,LABEL,SERIAL,PARTTYPE']))
    def flatten(rows):
        for row in rows:
            yield row
            yield from flatten(row.get('children', []))
    rows = list(flatten(data['blockdevices']))
    swap_sources = set()
    for line in Path('/proc/swaps').read_text().splitlines()[1:]:
        name = line.split()[0]
        if not name.startswith('/dev/'):
            swap_sources.add(run(['findmnt', '-n', '-o', 'SOURCE', '--target', name]).split('[')[0])
    for row in rows:
        if row['path'] in swap_sources: row['_backs_swap'] = True
    def inherit(row, serial=''):
        serial = row.get('serial') or serial
        row['_drive_hash'] = hashlib.sha256(serial.encode()).hexdigest()
        for child in row.get('children', []): inherit(child, serial)
    for row in data['blockdevices']: inherit(row)
    return rows


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
    if base.is_symlink() or target.is_symlink(): raise file_refusal('Thumbnail cache is symlinked; manage it at its source.', base if base.is_symlink() else target)
    return target


def paru_cache():
    # Use the documented default only, never an arbitrary request path or XDG override.
    base = Path.home() / '.cache'
    target = base / 'paru'
    for path in (base, target):
        if path.is_symlink(): raise file_refusal('Paru cache path is symlinked.', path)
        if path.exists() and (not path.is_dir() or path.stat().st_uid != os.getuid()):
            raise ValueError('Paru cache must be a directory owned by the current user.')
    return target


def size_text(total):
    return f'{total / 2**30:.1f} GiB' if total >= 2**30 else f'{total / 2**20:.1f} MiB'


def cache_size(path):
    """Bound each visible-page refresh to 500 ms / 200000 entries, never follow links."""
    if os.environ.get('BLANKWEAVE_STORAGE_VISIBLE') != '1': return 'Open Storage to measure'
    total = count = 0
    deadline = time.monotonic() + .5
    try:
        if not path.exists(): return '0 B'
        if path.is_symlink(): return 'Unavailable (symlink)'
        pending = [path]
        while pending:
            with os.scandir(pending.pop()) as entries:
                for entry in entries:
                    info = entry.stat(follow_symlinks=False)
                    if stat.S_ISDIR(info.st_mode): pending.append(Path(entry.path))
                    if not stat.S_ISLNK(info.st_mode): total += info.st_blocks * 512
                    count += 1
                    if count >= 200000 or time.monotonic() >= deadline:
                        return f'At least {size_text(total)} (still counting)'
        return size_text(total)
    except OSError:
        return 'Unavailable (could not read cache)'


def clean_paru():
    cache = paru_cache()
    if not cache.exists(): return 'No Paru cache exists.'
    # Descriptor-relative deletion cannot follow a swapped cache/clone symlink.
    parent = os.open(cache.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        if os.fstat(parent).st_uid != os.getuid(): raise ValueError('Paru cache parent ownership changed.')
        fd = os.open('paru', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    finally:
        os.close(parent)
    try:
        if os.fstat(fd).st_uid != os.getuid(): raise ValueError('Paru cache ownership changed.')
        try: info = os.stat('clone', dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError: return 'No Paru build cache exists.'
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise file_refusal('Paru clone cache must be an owned directory, not a symlink.', cache / 'clone')
        # Refuse foreign-owned contents before deleting anything. Symlinks are only unlinked.
        clone = cache / 'clone'
        for directory, dirs, files in os.walk(clone, followlinks=False):
            for name in ['.', *dirs, *files]:
                if (Path(directory) / name).lstat().st_uid != os.getuid():
                    raise ValueError('Paru build cache contains files owned by another user.')
        shutil.rmtree('clone', dir_fd=fd)
    finally:
        os.close(fd)
    return 'Paru build directories and downloaded sources cleared. Future builds will download sources again.'


def status(domain):
    if domain == 'disk-usage':
        usage = shutil.disk_usage(Path.home())
        cache = thumbnail_cache()
        stamp = cache.stat().st_mtime_ns if cache.exists() else None
        return state('Directory scans run only when requested and stay on one filesystem. Cache sizes are bounded estimates. Cleanup requires confirmation; package versions are retained for rollback and offline repair.',
                     [f'Pacman package cache: {cache_size(Path("/var/cache/pacman/pkg"))}',
                      f'Paru cache: {cache_size(paru_cache())}',
                      f'Home filesystem: {usage.used / 2**30:.1f} GiB used / {usage.total / 2**30:.1f} GiB total; {usage.free / 2**30:.1f} GiB free'],
                     [action('pacman-clean', 'Clean pacman package cache', confirm='Keep the last three package versions and one version of uninstalled packages. Never empty this cache: rollback and offline repair depend on it.'),
                      action('paru-clean', 'Clean Paru build cache', confirm='Delete Paru clone build directories, downloaded sources (including VCS sources), and locally built packages? Future builds must download them again. Installed packages are unchanged.'),
                      action('scan', 'Scan directory usage', [field('folder', 'Directory', str(Path.home()))], cancellable=True),
                      action('preview-cleanup', 'Review thumbnail cleanup', cancellable=True)] +
                     ([action('cleanup', 'Clear thumbnail cache', confirm=f'Delete generated thumbnails in {cache}? Applications will recreate them.')] if cache.exists() else []),
                     [str(cache), stamp])
    if not installed('lsblk'): return state(notices=[missing('util-linux')])
    rows = blocks()
    if domain == 'disk-health':
        disks = health_disks(rows)
        options = [choice(r['path'], f'{r["path"]} ({r["size"] / 2**30:.1f} GiB)') for r in disks]
        actions = []
        if installed('smartctl') and options:
            target = field('device', 'Drive', options[0]['value'], options)
            actions = [action('health', 'Read drive health', [target]),
                       action('self-test', 'Start short self-test', [target], 'Start a drive self-test. Read health again later to see the result.')]
        notices = [missing('smartmontools')] if not installed('smartctl') else []
        if not options: notices.append(notice('no-device', 'No physical drives found', 'Connect a physical drive, then refresh to check available health information.'))
        return state('Health telemetry requires smartmontools and administrator authorization. Unsupported telemetry does not mean a drive is healthy.', [p['label'] for p in options], actions, stable(disks), notices)
    inventory = drive_inventory(rows)
    actions = []
    for row in inventory:
        if not installed('udisksctl'): row['commands'] = []
        if row['protected'] or not installed('udisksctl'): continue
        for command in row['commands']:
            actions.append(action(command + ':' + (row['ejectIdentity'] if command == 'eject' else row['identity']), command.capitalize(),
                                  [field('password', 'Passphrase', secret=True)] if command == 'unlock' else [], confirm='Unmount every partition on this drive before ejecting?' if command == 'eject' and row['busy'] else ''))
    result = state('System drives are read-only. Removable media use UDisks as your user; busy filesystems must be closed before unmounting.',
                   actions=actions, identity=stable(rows), notices=([missing('udisks2')] if not installed('udisksctl') else []) + ([] if inventory else [notice('no-device', 'No removable drives connected', 'Connect a drive and refresh.')]))
    result['drives'] = inventory
    return result


def drive_identity(row):
    # Only the digest crosses the process boundary, never the hardware serial.
    sequence = Path('/sys/dev/block') / str(row.get('maj:min', 'unknown')) / 'diskseq'
    diskseq = sequence.read_text().strip() if sequence.exists() else ''
    return hashlib.sha256(json.dumps([row['path'], row.get('uuid'), row.get('serial'), row.get('_drive_hash'), row.get('maj:min'), row.get('size'), diskseq]).encode()).hexdigest()


def drive_inventory(rows):
    by_path = {r['path']: r for r in rows}
    protected = set()
    external = {r['path'] for r in removable(rows)}
    def family(row):
        found = {row['path']}
        for child in row.get('children', []): found |= family(child)
        return found
    for row in rows:
        mounts = row.get('mountpoints') or []
        if any(m == '[SWAP]' or m in ('/', '/boot', '/home') or (m and (m.startswith('/boot/') or m.startswith('/home/'))) for m in mounts) or row.get('fstype') == 'swap' or row.get('_backs_swap') or str(row.get('parttype', '')).lower() == 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b':
            protected.add(row['path'])
    # Propagate through the whole ancestor disk, including encrypted/LVM layers.
    changed = True
    while changed:
        before = len(protected)
        for row in rows:
            relatives = family(row)
            if relatives & protected: protected |= relatives
        changed = len(protected) != before
    result = []
    for row in by_path.values():
        mounted = any(row.get('mountpoints') or [])
        if row['path'] not in external and mounted and row['path'] not in protected: continue
        if row.get('type') not in ('disk', 'part', 'crypt', 'lvm'): continue
        readonly = row['path'] in protected
        regular = row.get('fstype') not in (None, '', 'crypto_LUKS', 'swap')
        commands = ([] if readonly else (['unmount' if mounted else 'mount'] if regular else []))
        if not readonly and row.get('fstype') == 'crypto_LUKS': commands += ['lock' if row.get('children') else 'unlock']
        disk = next((r for r in rows if r.get('type') == 'disk' and row['path'] in family(r)), None)
        if not readonly and disk and disk['path'] not in protected: commands += ['eject']
        busy = any(any(by_path.get(path, {}).get('mountpoints') or []) for path in family(disk or row))
        result.append(dict(device=row['path'], ejectIdentity=drive_identity(disk or row), identity=drive_identity(row), protected=readonly, busy=busy,
                           label=row.get('label') or row['path'], size=size_text(row.get('size') or 0),
                           filesystem=row.get('fstype') or 'No filesystem', mountpoint=', '.join(filter(None, row.get('mountpoints') or [])) or 'Not mounted', commands=commands))
    return result



def apply(domain, request):
    command = request['action']
    if domain == 'disk-usage':
        if command == 'pacman-clean': return privileged('package-cache-clean')
        if command == 'paru-clean': return clean_paru()
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
        if ':' not in command: raise ValueError('Unmount all filesystems first; refresh and select the drive again.')
        command, captured = command.split(':', 1)
        rows = blocks()
        inventory = drive_inventory(rows)
        target = next((row for row in inventory if row['identity'] == captured), None)
        if not target or target['protected'] or command not in target['commands']:
            raise ValueError('The drive changed or is protected. Refresh before trying again.')
        device = target['device']
        if command == 'eject' and target['busy']:
            if request.get('confirmed') is not True: raise ValueError('Confirm unmounting this drive before ejecting.')
            disk = next(r for r in rows if r['path'] == device)
            def unmount_children(row):
                for child in row.get('children', []): unmount_children(child)
                if any(row.get('mountpoints') or []):
                    fresh = next((r for r in blocks() if r['path'] == row['path']), None)
                    if not fresh or drive_identity(fresh) != drive_identity(row): raise ValueError('Drive identity changed.')
                    if next(r for r in drive_inventory(blocks()) if r['device'] == row['path'])['protected']: raise ValueError('System drive is protected.')
                    run(['udisksctl', 'unmount', '--block-device', row['path']], timeout=120)
                    if any(next((r for r in blocks() if r['path'] == row['path']), {}).get('mountpoints') or []): raise ValueError('The filesystem is still mounted.')
            unmount_children(disk)
        fresh = next((r for r in blocks() if r['path'] == device), None)
        if not fresh or drive_identity(fresh) != captured: raise ValueError('Drive identity changed.')
        if next(r for r in drive_inventory(blocks()) if r['device'] == device)['protected']: raise ValueError('System drive is protected.')
        if command == 'unlock':
            run(['udisksctl', 'unlock', '--block-device', device, '--key-file', '/dev/stdin'], input=require(request, 'password'), timeout=120)
        else:
            run(['udisksctl', 'power-off' if command == 'eject' else command, '--block-device', device], timeout=120)
        observed = next((r for r in blocks() if r['path'] == device), None)
        if command == 'eject':
            if observed: raise ValueError('The drive is still present; power-off was not verified.')
        else:
            if not observed or drive_identity(observed) != captured: raise ValueError('Drive identity changed during readback.')
            if command in ('unlock', 'lock'):
                if bool(observed.get('children')) != (command == 'unlock'): raise ValueError('The encrypted volume state was not observed.')
            elif bool(any(observed.get('mountpoints') or [])) != (command == 'mount'): raise ValueError('The requested mount state was not observed.')
        return command.capitalize() + ' verified for ' + device + '.'
    raise ValueError('Unknown storage operation.')
