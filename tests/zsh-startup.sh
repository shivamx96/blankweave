#!/usr/bin/env bash
# All package fixtures and dotfiles stay in a disposable home.
set -euo pipefail
if ! command -v zsh >/dev/null; then
    printf 'SKIP: zsh is unavailable.\n'
    exit 0
fi
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repository" <<'PY'
import os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    temporary = pathlib.Path(directory)
    for packages in (False, True):
        for personal in (False, True):
            home = temporary / f'{packages}-{personal}'
            home.mkdir()
            share = home / 'packages'
            shell = home / '.local/share/blankweave/shell'
            shell.mkdir(parents=True)
            (shell / 'p10k.zsh').write_text((root / 'defaults/shell/p10k.zsh').read_text() + '\nprint -r -- fallback >> "$TRACE"\n')
            (shell / 'zsh-keys.zsh').write_text((root / 'defaults/shell/zsh-keys.zsh').read_text() + '\nprint -r -- keys >> "$TRACE"\n')
            completions = home / '.local/share/zsh/site-functions'
            completions.mkdir(parents=True)
            (completions / '_fixture_command').write_text('#compdef fixture-command\n_arguments "1:item:(one two)"\n')
            override = home / '.config/blankweave/overrides/zsh.zsh'
            override.parent.mkdir(parents=True)
            override.write_text('print -r -- override >> "$TRACE"\n')
            source = (root / 'defaults/shell/.zshrc').read_text()
            # Map only literal packaged paths; no production test backdoor.
            source = source.replace('/usr/share/', str(share) + '/')
            (home / '.zshrc').write_text(source + '\nprint -r -- tail >> "$TRACE"\n')
            (home / '.zshenv').write_text('unsetopt GLOBAL_RCS\n')
            if personal:
                (home / '.p10k.zsh').write_text('print -r -- personal >> "$TRACE"\n')
            if packages:
                paths = {
                    'oh-my-zsh/lib/git.zsh': 'git-lib',
                    'oh-my-zsh/plugins/git/git.plugin.zsh': 'git-plugin',
                    'zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh': 'suggestions',
                    'zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh': 'history',
                    'zsh/plugins/fzf-tab-git/fzf-tab.plugin.zsh': 'fzf-tab',
                    'fzf/key-bindings.zsh': 'fzf-keys',
                    'fzf/completion.zsh': 'fzf-completion',
                    'zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh': 'highlight',
                }
                for path, label in paths.items():
                    file = share / path
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_text(f'print -r -- {label} >> "$TRACE"\n')
                theme = share / 'zsh-theme-powerlevel10k/powerlevel10k.zsh-theme'
                theme.parent.mkdir(parents=True)
                theme.write_text('[[ $POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD == true ]] || print WIZARD >&2\nprint -r -- prompt >> "$TRACE"\nfunction p10k() { print -r -- "$*" > "$HOME/configure"; }\n')
            binary = home / 'bin'
            binary.mkdir()
            for command in ('git', 'curl', 'wget'):
                file = binary / command
                file.write_text('#!/bin/sh\necho NETWORK >> "$TRACE"\nexit 99\n')
                file.chmod(0o755)
            # zoxide is an installed executable integration, not a network loader.
            file = binary / 'zoxide'
            file.write_text('#!/bin/sh\nexit 0\n')
            file.chmod(0o755)
            trace = home / 'trace'
            env = {'HOME': str(home), 'ZDOTDIR': str(home), 'PATH': str(binary) + ':/usr/bin:/bin',
                   'TERM': 'xterm-256color', 'TRACE': str(trace)}
            result = subprocess.run(['zsh', '-i', '-c', 'exit'], env=env, capture_output=True)
            assert result.returncode == 0 and not result.stderr and not result.stdout, result
            order = trace.read_text().splitlines()
            assert 'NETWORK' not in order
            assert order[-3:] == ['keys', 'override', 'tail'], order
            assert ('personal' in order) == personal
            assert ('fallback' in order) != personal
            completion = subprocess.run(['zsh', '-i', '-c', '[[ ${_comps[fixture-command]} == _fixture_command ]]'], env=env, capture_output=True)
            assert completion.returncode == 0 and not completion.stderr
            if packages:
                assert order.index('highlight') > order.index('fzf-completion')
                assert order.index('fzf-completion') < order.index('fzf-tab') < order.index('suggestions')
                result = subprocess.run(['zsh', '-i', '-c', 'p10k configure'], env=env, capture_output=True)
                assert result.returncode == 0 and not result.stderr
                assert (home / 'configure').read_text().strip() == 'configure'
print('Offline zsh startup matrix passed (packages present/absent, personal/default prompt).')
PY
