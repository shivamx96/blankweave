"""Private coordination/scratch paths shared by Settings and shell callers.

Saved preferences and durable ledgers do not belong here. Import is read-only.
"""
import os
from pathlib import Path


def session_runtime(run_root=Path('/run/user'), account=None):
    """The session's runtime directory, even for a caller that lost the variable.

    The installer runs helpers as the user through sudo, which drops
    XDG_RUNTIME_DIR. Those helpers must still take the same locks as the live
    session, so fall back to the account's own /run/user/<uid>. An isolated
    HOME (every test) never equals the account's real home and is left alone.
    """
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    if runtime:
        return Path(runtime)
    try:
        if account is None:
            import pwd
            entry = pwd.getpwuid(os.getuid())
            account = (entry.pw_uid, entry.pw_dir)
        uid, home = account
        candidate = Path(run_root) / str(uid)
        if Path.home() == Path(home) and candidate.is_dir() and candidate.stat().st_uid == uid:
            return candidate
    except (KeyError, OSError):
        pass
    return None


def runtime_dir():
    runtime = session_runtime()
    root = (runtime / 'blankweave' if runtime else
            Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'blankweave/locks')
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    return root


def runtime_path(name):
    if not name or Path(name).name != name:
        raise ValueError('Expected a coordination file name')
    return runtime_dir() / name


if __name__ == '__main__':
    import sys
    print(runtime_path(sys.argv[1]))
