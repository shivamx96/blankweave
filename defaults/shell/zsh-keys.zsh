# Standalone ZLE bindings: no plugins or network access.
() {
    zmodload zsh/terminfo
    local map capability widget sequence
    local -a pairs
    pairs=(khome beginning-of-line kend end-of-line kdch1 delete-char
           kLFT5 backward-word kRIT5 forward-word kDC5 kill-word
           kpp history-search-backward knp history-search-forward)
    for map in emacs viins; do
        # Normal mode (Ghostty/xterm), application mode, and Linux console.
        for sequence in $'\e[H' $'\eOH' $'\e[1~' $'\e[7~'; do
            bindkey -M "$map" "$sequence" beginning-of-line
        done
        for sequence in $'\e[F' $'\eOF' $'\e[4~' $'\e[8~'; do
            bindkey -M "$map" "$sequence" end-of-line
        done
        bindkey -M "$map" $'\e[3~' delete-char
        bindkey -M "$map" $'\e[1;5D' backward-word
        bindkey -M "$map" $'\e[1;5C' forward-word
        bindkey -M "$map" $'\e[3;5~' kill-word
        # Ghostty/xterm encode Ctrl+Backspace as BS; plain Backspace is DEL.
        # Leave BS alone on a terminal whose own Backspace sends it.
        [[ ${terminfo[kbs]} == $'\x08' ]] || bindkey -M "$map" $'\x08' backward-kill-word
        bindkey -M "$map" $'\e[127;5u' backward-kill-word
        bindkey -M "$map" $'\e[5~' history-search-backward
        bindkey -M "$map" $'\e[6~' history-search-forward
        for capability widget in "${pairs[@]}"; do
            [[ -n ${terminfo[$capability]} ]] && bindkey -M "$map" "${terminfo[$capability]}" "$widget"
        done
    done
    # Terminfo's SS3 Home/End require application mode. Keep hooks additive.
    if [[ ${terminfo[khome]} == $'\eOH' && -n ${terminfo[smkx]} && -n ${terminfo[rmkx]} ]]; then
        autoload -Uz add-zle-hook-widget
        _blankweave_keypad_init() { print -rn -- "${terminfo[smkx]}" }
        _blankweave_keypad_finish() { print -rn -- "${terminfo[rmkx]}" }
        add-zle-hook-widget line-init _blankweave_keypad_init
        add-zle-hook-widget line-finish _blankweave_keypad_finish
    fi
    return 0
}
