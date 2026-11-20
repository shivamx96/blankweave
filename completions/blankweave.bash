# Loaded by bash-completion from its standard per-user completion directory.
_blankweave() {
    local current=${COMP_WORDS[COMP_CWORD]} command=${COMP_WORDS[1]:-}
    local words='welcome version setup settings update rollback doctor theme webapp uninstall help'
    if (( COMP_CWORD > 1 )); then
        case "$command" in
            theme) words='list status set mode toggle sync lint' ;;
            webapp) words='list install remove sync' ;;
            settings) words="$(blankweave settings --list 2>/dev/null | cut -f1) --list" ;;
            help) ;;
            *) words='--non-interactive --check --dry-run --yes --to --reapply --allow-upgrade --full --normal --report --apply --purge-config' ;;
        esac
    fi
    words+=' --help -h --version -V'
    mapfile -t COMPREPLY < <(compgen -W "$words" -- "$current")
}
complete -F _blankweave blankweave
