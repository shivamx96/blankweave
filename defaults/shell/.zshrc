# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Packages are installed during apply; startup never downloads shell code.
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
PROMPT='%n@%m %~ %# '
() {
    local file
    # zsh-completions installs functions into the standard site-functions fpath.
    # User-installed completions use the XDG site-functions directory.
    fpath=("${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions" $fpath)
    autoload -Uz compinit
    compinit -i
    # fzf-tab must wrap completion before autosuggestions wraps the widgets.
    for file in /usr/share/oh-my-zsh/lib/git.zsh \
                /usr/share/oh-my-zsh/plugins/git/git.plugin.zsh \
                /usr/share/fzf/key-bindings.zsh \
                /usr/share/fzf/completion.zsh \
                /usr/share/zsh/plugins/fzf-tab-git/fzf-tab.plugin.zsh \
                /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
                /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh; do
        [[ ! -r $file ]] || source "$file"
    done
    if [[ -r $HOME/.p10k.zsh ]]; then
        source "$HOME/.p10k.zsh"
    else
        file="${XDG_DATA_HOME:-$HOME/.local/share}/blankweave/shell/p10k.zsh"
        [[ ! -r $file ]] || source "$file"
    fi
    file=/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
    [[ ! -r $file ]] || source "$file"
    return 0
}

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

# History
HISTSIZE=10000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# Shell integrations
(( ! $+commands[zoxide] )) || eval "$(zoxide init --cmd cd zsh)"

# Highlighting wraps widgets only after all other plugins/integrations load.
[[ ! -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] ||
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Aliases
alias ls='ls --color'
alias lsa='ls -lha'
alias lzg='lazygit'
alias lzd='lazydocker'
alias update-blankweave='blankweave update'

# Updating PATH with Zed
export PATH=$HOME/.local/bin:$PATH

# Apply after plugins and shell integrations; personal overrides still win.
() {
    local keys="${XDG_DATA_HOME:-$HOME/.local/share}/blankweave/shell/zsh-keys.zsh"
    [[ -r $keys ]] && source "$keys"
}

if [[ -r "$HOME/.config/blankweave/overrides/zsh.zsh" ]]; then
    source "$HOME/.config/blankweave/overrides/zsh.zsh"
fi

#############################################################################
### ANY CUSTOM CONFIGS GO BELOW THIS LINE
#############################################################################
