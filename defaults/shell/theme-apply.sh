#!/usr/bin/env bash
#
# Apply the active Blankweave theme.
#
# A theme is a directory holding theme.json with a dark and a light mode, each
# carrying the shell palette, the lock-screen treatment, a wallpaper, and the
# names of the matching application themes. Bundled themes are deployed to
# ~/.local/share/blankweave/themes/<id>/ and a user theme in
# ~/.config/blankweave/themes/<id>/ shadows a bundled one of the same id.
#
# This script is the only writer of ~/.config/blankweave/theme.json, which holds
# both the persisted selection and the resolved values of the active mode, and
# of every config rendered from a *.tmpl next to it. Templates use
# {{path}} placeholders resolved against the resolved theme, with an optional
# {{path:format}} override for colours (css, rgb, hypr, plymouth).
#
# Two parts of a theme need root and are not applied here: the Papirus folder
# colour and the Plymouth boot splash. This script stages the rendered splash
# under ~/.local/share/blankweave/plymouth/ and reports both as `system.pending`
# in `status`; `blankweave theme sync` (scripts/theme-system.sh) installs them.
#
# Usage:
#   theme-apply.sh [apply]          re-render the persisted selection
#   theme-apply.sh set <theme>      switch theme, keeping the current mode
#   theme-apply.sh mode <dark|light>
#   theme-apply.sh toggle           flip between dark and light
#   theme-apply.sh list             JSON array of the available themes
#   theme-apply.sh status           JSON of the active theme, plus whether the
#                                   privileged parts still need a sync

set -euo pipefail

DOTS_DIR=$HOME/.local/share/blankweave
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}
BLANKWEAVE_CONFIG_DIR=$CONFIG_DIR/blankweave
STATE_FILE=$BLANKWEAVE_CONFIG_DIR/theme.json
LEGACY_STATE_FILE=$DOTS_DIR/theme
PLYMOUTH_STAGE=$DOTS_DIR/plymouth/blankweave
DEFAULT_THEME=obsidian
DEFAULT_MODE=dark
# Cursor size is rice geometry, matching HYPRCURSOR_SIZE in env.lua.
CURSOR_SIZE=24

# Where the privileged parts land; overridable so the tests never look at the
# real system. theme-system.sh honours the same variables.
ICONS_DIR=${BLANKWEAVE_ICONS_DIR:-/usr/share/icons}
PLYMOUTH_DIR=${BLANKWEAVE_PLYMOUTH_DIR:-/usr/share/plymouth/themes/blankweave}
PLYMOUTH_FILES=(blankweave.plymouth blankweave.script logo.png progress_bar.png progress_box.png)

# Every token Theme.qml and the templates may reference. A theme missing one
# is rejected rather than rendered with a hole in it.
REQUIRED_COLORS=(
    canvas barSurface barHighlight panelSurface surface surfaceRaised
    surfaceHover surfacePressed scrim text textMuted accent accentBright
    accentSurface outline outlineStrong divider success warning critical
)

# Single-pass substitution: a rendered value can never be mistaken for a
# placeholder, so no staging through intermediate markers is needed.
# shellcheck disable=SC2016
RENDER_PROGRAM='
def body: ltrimstr("#") | ascii_downcase | if length == 6 then . + "ff" else . end;
def is_color: type == "string" and test("^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$");
def hex_digit: if . >= 97 then . - 87 else . - 48 end;
def channel($at): body | .[$at:$at + 2] | explode | map(hex_digit) | .[0] * 16 + .[1];
def unit($at): channel($at) / 255 * 1000 | round / 1000 | tostring;
def render($format):
    if is_color then
        if $format == "css" then ascii_downcase
        elif $format == "rgb" then "#" + (body | .[0:6])
        elif $format == "hypr" then "rgba(" + body + ")"
        elif $format == "plymouth" then [unit(0), unit(2), unit(4)] | join(", ")
        else error("unknown colour format: " + $format)
        end
    elif type == "string" then .
    elif type == "number" or type == "boolean" then tostring
    else error("placeholder does not resolve to a scalar")
    end;
def lookup($path):
    ($ctx | getpath($path | split("."))) as $value
    | if $value == null then error("unknown placeholder: " + $path) else $value end;
$template
| gsub("\\{\\{(?<p>[A-Za-z0-9_.]+)(:(?<f>[a-z]+))?\\}\\}";
       (.f // $format) as $chosen | lookup(.p) | render($chosen))
'

THEME=$DEFAULT_THEME
MODE=$DEFAULT_MODE
RESOLVED=""

die() {
    printf 'theme-apply: %s\n' "$*" >&2
    exit 1
}

usage() {
    sed -n '/^# Usage:/,/^$/{s/^#\s\{0,1\}//p}' "${BASH_SOURCE[0]}"
}

valid_theme_id() {
    [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

theme_dir() {
    local id=$1 dir

    valid_theme_id "$id" || die "invalid theme id: $id"
    for dir in "$BLANKWEAVE_CONFIG_DIR/themes/$id" "$DOTS_DIR/themes/$id"; do
        if [[ -r $dir/theme.json ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

# The selection lives in the resolved state file. Before the first apply the
# pre-theme installs recorded only a mode in a plain-text file; honour it so an
# update never flips someone back to dark.
load_selection() {
    local theme mode legacy

    if [[ -r $STATE_FILE ]]; then
        theme=$(jq -r '.theme // empty' "$STATE_FILE" 2>/dev/null) || theme=""
        mode=$(jq -r '.mode // empty' "$STATE_FILE" 2>/dev/null) || mode=""
        [[ -n $theme ]] && THEME=$theme
        [[ -n $mode ]] && MODE=$mode
    elif [[ -r $LEGACY_STATE_FILE ]]; then
        IFS= read -r legacy < "$LEGACY_STATE_FILE" || true
        [[ $legacy == light ]] && MODE=light
    fi
    return 0
}

resolve_theme() {
    local id=$1 mode=$2 dir required

    dir=$(theme_dir "$id") || die "unknown theme: $id"
    required=$(printf '%s\n' "${REQUIRED_COLORS[@]}" | jq -R . | jq -s .)
    jq -e --arg id "$id" --arg mode "$mode" --arg dir "$dir" --argjson required "$required" '
        .modes[$mode] as $variant
        | if $variant == null then error("theme \($id) has no \($mode) mode") else . end
        | ($required - (($variant.colors // {}) | keys)) as $missing
        | if ($missing | length) > 0
          then error("theme \($id) \($mode) mode is missing colours: \($missing | join(", "))")
          else . end
        | (["ghostty", "iconTheme", "cursorTheme"] - ($variant | keys)) as $missing
        | if ($missing | length) > 0
          then error("theme \($id) \($mode) mode is missing: \($missing | join(", "))")
          else . end
        | def path_in_theme: if . == null or . == "" then null
                             elif startswith("/") then .
                             else "\($dir)/\(.)" end;
        $variant + {
            theme: $id,
            mode: $mode,
            name: .name,
            wallpaper: ($variant.wallpaper | path_in_theme),
            folderColor: (.folderColor // null),
            plymouth: (if .plymouth == null then null
                       else { logo: (.plymouth.logo | path_in_theme),
                              progressBar: (.plymouth.progressBar | path_in_theme) } end),
            modes: (.modes | map_values({label, ghostty, iconTheme, cursorTheme, colors}))
          }
    ' "$dir/theme.json"
}

render_template() {
    local format=$1 template=$2 output=$3 staged

    if [[ ! -r $template ]]; then
        printf 'theme-apply: template not found, skipped: %s\n' "$template" >&2
        return 0
    fi
    mkdir -p "$(dirname "$output")"
    staged=$(mktemp "$(dirname "$output")/.$(basename "$output").XXXXXX")
    if ! jq -j --rawfile template "$template" --arg format "$format" \
            --argjson ctx "$RESOLVED" -n "$RENDER_PROGRAM" > "$staged"; then
        rm -f "$staged"
        die "failed to render $template"
    fi
    chmod 0644 "$staged"
    mv -f "$staged" "$output"
}

render_all() {
    render_template css "$DOTS_DIR/dunst/dunstrc.tmpl" "$DOTS_DIR/dunst/dunstrc"
    render_template css "$DOTS_DIR/ghostty/config.tmpl" "$DOTS_DIR/ghostty/config"
    render_template hypr "$DOTS_DIR/hypr/hyprlock-theme.conf.tmpl" "$DOTS_DIR/hypr/hyprlock-theme.conf"
    render_template hypr "$DOTS_DIR/hypr/theme.lua.tmpl" "$BLANKWEAVE_CONFIG_DIR/theme.lua"
    if [[ -r $DOTS_DIR/voxtype/config.toml.tmpl ]]; then
        render_template css "$DOTS_DIR/voxtype/config.toml.tmpl" "$DOTS_DIR/voxtype/config.toml"
    fi
    render_template plymouth "$PLYMOUTH_STAGE/blankweave.script.tmpl" "$PLYMOUTH_STAGE/blankweave.script"
    stage_plymouth_artwork
}

# The boot splash is installed by root from this user-owned staging copy, so
# the theme's tinted artwork is placed next to the rendered script. A theme
# without artwork leaves an incomplete stage that theme-system.sh refuses to
# install rather than a splash with the previous theme's logo.
stage_plymouth_artwork() {
    local logo bar staged

    [[ -d $PLYMOUTH_STAGE ]] || return 0
    logo=$(jq -r '.plymouth.logo // empty' <<< "$RESOLVED")
    bar=$(jq -r '.plymouth.progressBar // empty' <<< "$RESOLVED")
    if [[ -f $logo && -f $bar ]]; then
        for file in "$logo:logo.png" "$bar:progress_bar.png"; do
            staged=$(mktemp "$PLYMOUTH_STAGE/.${file##*:}.XXXXXX")
            cp -f "${file%%:*}" "$staged"
            chmod 0644 "$staged"
            mv -f "$staged" "$PLYMOUTH_STAGE/${file##*:}"
        done
    else
        rm -f "$PLYMOUTH_STAGE/logo.png" "$PLYMOUTH_STAGE/progress_bar.png"
    fi
}

# Quickshell watches this file, so replace its contents with one write rather
# than renaming a staged copy out from under the watch.
write_state() {
    mkdir -p "$BLANKWEAVE_CONFIG_DIR"
    printf '%s\n' "$RESOLVED" > "$STATE_FILE"
}

apply_desktop_preferences() {
    local scheme gtk_theme prefer_dark dir icon_theme cursor_theme

    icon_theme=$(jq -r '.iconTheme' <<< "$RESOLVED")
    cursor_theme=$(jq -r '.cursorTheme' <<< "$RESOLVED")
    if [[ $MODE == light ]]; then
        scheme=prefer-light
        prefer_dark=0
    else
        scheme=prefer-dark
        prefer_dark=1
    fi

    # The GTK theme name is pinned to Adwaita in both modes; the mode travels
    # as the portal colour scheme and as gtk-application-prefer-dark-theme in
    # settings.ini. Chromium (every Electron app) derives the colour scheme it
    # hands the page from the window background of the GTK theme it has
    # loaded, and recomputes it whenever gtk-theme-name changes. With Adwaita
    # that background follows the portal, because the portal toggles GTK's
    # prefer-dark-theme and Adwaita's dark variant with it; the name
    # "Adwaita-dark" evaluated light instead and overrode the portal's answer,
    # so after the first switch Electron apps stopped following the mode.
    gtk_theme=Adwaita

    # Portal-aware apps (libadwaita, Ghostty, browsers) follow gsettings.
    if command -v gsettings > /dev/null; then
        gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2> /dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2> /dev/null || true
        gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2> /dev/null || true
        gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" 2> /dev/null || true
        gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" 2> /dev/null || true
    fi

    # GTK3 apps on Hyprland have no settings daemon and read these files.
    for dir in gtk-3.0 gtk-4.0; do
        mkdir -p "$CONFIG_DIR/$dir"
        printf '[Settings]\ngtk-application-prefer-dark-theme=%s\ngtk-theme-name=Adwaita\ngtk-icon-theme-name=%s\ngtk-cursor-theme-name=%s\ngtk-cursor-theme-size=%s\n' \
            "$prefer_dark" "$icon_theme" "$cursor_theme" "$CURSOR_SIZE" > "$CONFIG_DIR/$dir/settings.ini"
    done
}

apply_wallpaper() {
    local wallpaper

    wallpaper=$(jq -r '.wallpaper // empty' <<< "$RESOLVED")
    [[ -n $wallpaper && -f $wallpaper ]] || return 0
    # Wallpaper availability must never keep the palette from changing.
    [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v awww > /dev/null || return 0
    bash "$DOTS_DIR/shell/wallpaper.sh" set "$wallpaper" > /dev/null 2>&1 || true
}

reload_services() {
    local link voxtype_state voxtype_state_file

    # Symlink mtimes wake inotify-based readers such as Ghostty.
    for link in "$CONFIG_DIR/ghostty/config" "$CONFIG_DIR/dunst/dunstrc"; do
        if [[ -L $link ]]; then
            touch -h "$link" 2> /dev/null || true
        fi
    done
    # Reload Dunst in place so the palette changes without discarding history.
    if command -v dunstctl > /dev/null; then
        dunstctl reload "$DOTS_DIR/dunst/dunstrc" 2> /dev/null || true
    fi
    # VoxType reads its OSD palette from the rendered config. Restart only an
    # idle running daemon: a theme switch must never discard active speech.
    if command -v systemctl > /dev/null \
        && systemctl --user is-active --quiet voxtype.service 2> /dev/null; then
        voxtype_state=idle
        voxtype_state_file=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voxtype/state
        if [[ -r $voxtype_state_file ]]; then
            voxtype_state=$(< "$voxtype_state_file")
        fi
        if [[ $voxtype_state != recording && $voxtype_state != transcribing \
            && $voxtype_state != streaming ]]; then
            systemctl --user restart voxtype.service 2> /dev/null || true
        fi
    fi
    # Ghostty notices the touched symlink and reloads, but a surface that is
    # already open keeps the light/dark theme pair it resolved at creation;
    # only the explicit reload-config action re-resolves it. Ghostty is D-Bus
    # activatable, so check it owns its name first or the call would launch it.
    if command -v gdbus > /dev/null \
        && [[ $(gdbus call --session --dest org.freedesktop.DBus \
                --object-path /org/freedesktop/DBus \
                --method org.freedesktop.DBus.NameHasOwner \
                com.mitchellh.ghostty 2> /dev/null) == "(true,)" ]]; then
        gdbus call --session --dest com.mitchellh.ghostty \
            --object-path /com/mitchellh/ghostty \
            --method org.gtk.Actions.Activate reload-config '[]' '{}' > /dev/null 2>&1 || true
    fi
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl > /dev/null; then
        hyprctl reload > /dev/null 2>&1 || true
        # env() in the config only seeds a new session; a running compositor
        # switches its cursor, and tells clients through XCURSOR, here.
        hyprctl setcursor "$(jq -r '.cursorTheme' <<< "$RESOLVED")" "$CURSOR_SIZE" > /dev/null 2>&1 || true
    fi
}

# Whether the privileged parts of the given resolved theme are installed. A
# part that is not present on this machine at all (no Papirus, no Plymouth
# theme staged) is never pending; there is nothing a sync could do.
system_status() {
    local resolved=$1 wanted current link file
    local folders=false splash=false

    wanted=$(jq -r '.folderColor // empty' <<< "$resolved")
    link=$ICONS_DIR/Papirus/48x48/places/folder.svg
    if [[ -n $wanted && -L $link ]]; then
        current=$(readlink "$link")
        current=${current#folder-}
        [[ ${current%.svg} == "$wanted" ]] || folders=true
    fi

    if [[ -f $PLYMOUTH_STAGE/logo.png ]]; then
        for file in "${PLYMOUTH_FILES[@]}"; do
            [[ -f $PLYMOUTH_STAGE/$file ]] || continue
            cmp -s "$PLYMOUTH_STAGE/$file" "$PLYMOUTH_DIR/$file" || splash=true
        done
    fi

    jq -n --argjson folders "$folders" --argjson splash "$splash" \
        '{folders: $folders, bootSplash: $splash, pending: ($folders or $splash)}'
}

list_themes() {
    local -A seen=()
    local source root file id entries=()

    for source in user bundled; do
        case $source in
            user) root=$BLANKWEAVE_CONFIG_DIR/themes ;;
            bundled) root=$DOTS_DIR/themes ;;
        esac
        for file in "$root"/*/theme.json; do
            [[ -r $file ]] || continue
            id=$(basename "$(dirname "$file")")
            valid_theme_id "$id" || continue
            [[ -n ${seen[$id]:-} ]] && continue
            seen[$id]=1
            entries+=("$(jq -c --arg id "$id" --arg source "$source" '{
                id: $id,
                name: (.name // $id),
                description: (.description // ""),
                source: $source,
                modes: (.modes // {} | to_entries
                        | map({mode: .key, label: (.value.label // .key), accent: (.value.colors.accent // null)}))
            }' "$file" 2> /dev/null || printf '{"id":"%s","name":"%s","source":"%s","invalid":true}' "$id" "$id" "$source")")
        done
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        printf '[]\n'
    else
        printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.name)'
    fi
}

main() {
    local command=${1:-apply}
    shift || true

    load_selection
    if [[ -n ${BLANKWEAVE_SETUP_THEME:-} ]]; then
        THEME=$BLANKWEAVE_SETUP_THEME
    fi
    if [[ -n ${BLANKWEAVE_SETUP_MODE:-} ]]; then
        MODE=$BLANKWEAVE_SETUP_MODE
    fi
    case $command in
        apply)
            [[ $# -eq 0 ]] || die "apply does not accept arguments"
            ;;
        set)
            [[ $# -eq 1 ]] || die "set requires a theme id"
            THEME=$1
            ;;
        mode)
            [[ $# -eq 1 ]] || die "mode requires dark or light"
            MODE=$1
            ;;
        toggle)
            [[ $# -eq 0 ]] || die "toggle does not accept arguments"
            if [[ $MODE == dark ]]; then MODE=light; else MODE=dark; fi
            ;;
        list)
            [[ $# -eq 0 ]] || die "list does not accept arguments"
            list_themes
            return 0
            ;;
        status)
            [[ $# -eq 0 ]] || die "status does not accept arguments"
            if [[ -r $STATE_FILE ]]; then
                RESOLVED=$(< "$STATE_FILE")
            else
                RESOLVED=$(resolve_theme "$THEME" "$MODE")
            fi
            jq --argjson system "$(system_status "$RESOLVED")" '. + {system: $system}' <<< "$RESOLVED"
            return 0
            ;;
        help|-h|--help)
            usage
            return 0
            ;;
        *)
            die "unknown command: $command"
            ;;
    esac

    [[ $MODE == dark || $MODE == light ]] || die "mode must be dark or light: $MODE"
    RESOLVED=$(resolve_theme "$THEME" "$MODE")
    render_all
    write_state
    apply_desktop_preferences
    apply_wallpaper
    reload_services
}

main "$@"
