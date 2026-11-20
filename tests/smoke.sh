#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n "$test_root" && -d "$test_root" ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

repository_version=$(head -n 1 "$repository/VERSION")
repository_release=unreleased
if release=$("$repository/scripts/verify-release.sh" "$repository" HEAD 2>/dev/null); then
    repository_release=$release
fi

version_output=$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" version
)
grep -Fxq "blankweave $repository_version ($repository_release)" <<< "$version_output"
grep -Fq 'installed:  not-recorded / not-recorded (not-recorded)' <<< "$version_output"
grep -Fq 'rollback floor: 0.1.0' <<< "$version_output"

grep -Fq 'Usage: blankweave doctor [--full|--normal] [--report]' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" doctor --help
)"

grep -Fq 'Usage: blankweave update [--check|--dry-run] [--reapply | --to vX.Y.Z] [--yes]' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" update --help
)"
grep -Fq 'Usage: blankweave rollback' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" rollback --help
)"
grep -Fq 'Usage: blankweave setup [--non-interactive]' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" setup --help
)"

# The old command name hands over to the new one so an installed
# `hyprarch update` can exec the fetched revision.
grep -Fxq "blankweave $repository_version ($repository_release)" \
    <<< "$(HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$repository/bin/hyprarch" version)"

if "$repository/bin/blankweave" unknown > /dev/null 2>&1; then
    printf 'Unknown CLI commands must fail.\n' >&2
    exit 1
else
    exit_code=$?
    [[ "$exit_code" -eq 2 ]] || {
        printf 'Unknown CLI command returned %s, expected 2.\n' "$exit_code" >&2
        exit 1
    }
fi

migration_repository=$test_root/repository
mkdir -p "$migration_repository/scripts"
cp -R "$repository/migrations" "$migration_repository/"
cp "$repository/scripts/release-version.sh" "$migration_repository/scripts/"
cp "$repository/VERSION" "$repository/MIN_ROLLBACK_VERSION" "$migration_repository/"
git -C "$migration_repository" init --quiet
git -C "$migration_repository" config user.name 'Blankweave CI'
git -C "$migration_repository" config user.email 'ci@blankweave.invalid'
git -C "$migration_repository" add .
git -C "$migration_repository" commit --quiet -m 'test fixture'

# The git-widget cache migration predates the rename and clears the old
# cache directory; a fresh install finds nothing there, an upgraded one has
# already had it relocated, so the fixture uses the path it actually clears.
mkdir -p "$test_root/cache/hyprarch"
touch "$test_root/cache/hyprarch/git-prs.json"
touch "$test_root/cache/hyprarch/git-login"

# The Steam shadow-entry migration removes only Blankweave's tagged launcher;
# a user's own steam.desktop at the same path is kept.
applications_dir=$test_root/home/.local/share/applications
mkdir -p "$applications_dir"
printf '[Desktop Entry]\nName=Steam\nExec=/missing/xwayland-launch.sh /usr/bin/steam %%U\nX-Blankweave-Entry=steam\n' \
    > "$applications_dir/steam.desktop"
printf '[Desktop Entry]\nName=Steam\nExec=/usr/bin/steam -custom %%U\n' \
    > "$applications_dir/steam-custom.desktop"

# XDG_DATA_HOME is passed explicitly: a developer's session may export it, and
# the migrations must act on the sandbox, never on the real home.
HOME="$test_root/home" \
    XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_CACHE_HOME="$test_root/cache" \
    XDG_DATA_HOME="$test_root/home/.local/share" \
    XDG_STATE_HOME="$test_root/state" \
    "$repository/scripts/run-migrations.sh" "$migration_repository"

[[ ! -e "$applications_dir/steam.desktop" ]]
grep -Fxq 'Exec=/usr/bin/steam -custom %U' "$applications_dir/steam-custom.desktop"

# The same migration must keep an untagged user launcher at the managed path.
printf '[Desktop Entry]\nName=Steam\nExec=/usr/bin/steam -mine %%U\n' > "$applications_dir/steam.desktop"
HOME="$test_root/home" XDG_DATA_HOME="$test_root/home/.local/share" \
    "$repository/migrations/20261011-drop-steam-shadow-entry.sh"
grep -Fxq 'Exec=/usr/bin/steam -mine %U' "$applications_dir/steam.desktop"

# The Thunar migration repoints only the stock, exo-backed terminal action.
thunar_dir=$test_root/home/.config/Thunar
empty_path=$test_root/empty-path
mkdir -p "$thunar_dir" "$empty_path"
printf '<actions>\n<action>\n\t<unique-id>1-1</unique-id>\n\t<command>exo-open --working-directory %%f --launch TerminalEmulator</command>\n</action>\n</actions>\n' \
    > "$thunar_dir/uca.xml"
chmod 600 "$thunar_dir/uca.xml"
for _ in 1 2; do
    HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" PATH="$empty_path:/usr/bin:/bin" \
        "$repository/migrations/20261112-thunar-terminal-action.sh"
done
if command -v exo-open >/dev/null 2>&1; then
    grep -Fq 'exo-open --working-directory %f' "$thunar_dir/uca.xml"
else
    grep -Fq '<command>ghostty --working-directory=%f</command>' "$thunar_dir/uca.xml"
    grep -Fq '<unique-id>1-1</unique-id>' "$thunar_dir/uca.xml"
    [[ $(stat -c %a "$thunar_dir/uca.xml") == 600 ]]
fi
printf '<actions><action><command>kitty -d %%f</command></action></actions>\n' > "$thunar_dir/uca.xml"
HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    "$repository/migrations/20261112-thunar-terminal-action.sh"
grep -Fq '<command>kitty -d %f</command>' "$thunar_dir/uca.xml"

# Fontconfig migration removes only our exact old link, including dangling links.
fontconfig_dir=$test_root/home/.config/fontconfig/conf.d
mkdir -p "$fontconfig_dir"
legacy_fontconfig=$fontconfig_dir/local.conf
fontconfig_migration=$repository/migrations/20261112-fontconfig-digit-prefix.sh
ln -s "$test_root/home/.local/share/blankweave/fontconfig/local.conf" "$legacy_fontconfig"
for _ in 1 2; do
    HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" "$fontconfig_migration"
done
[[ ! -L $legacy_fontconfig && ! -e $legacy_fontconfig ]]
# A live managed link is removed without deleting the deployed source.
managed_font=$test_root/home/.local/share/blankweave/fontconfig/local.conf
mkdir -p "$(dirname "$managed_font")"
printf 'managed fonts\n' > "$managed_font"
ln -s "$managed_font" "$legacy_fontconfig"
HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" "$fontconfig_migration"
[[ ! -L $legacy_fontconfig && -f $managed_font ]]
printf 'personal fonts\n' > "$legacy_fontconfig"
HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" "$fontconfig_migration"
[[ $(< "$legacy_fontconfig") == 'personal fonts' ]]
rm "$legacy_fontconfig"
for target in /foreign/fontconfig/local.conf ../missing.conf; do
    ln -s "$target" "$legacy_fontconfig"
    HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" "$fontconfig_migration"
    [[ $(readlink "$legacy_fontconfig") == "$target" ]]
    rm "$legacy_fontconfig"
done
mkdir "$legacy_fontconfig"
HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" "$fontconfig_migration"
[[ -d $legacy_fontconfig ]]

state_dir=$test_root/state/blankweave
[[ $(< "$state_dir/repository") == "$migration_repository" ]]
[[ $(< "$state_dir/installed-revision") == "$(git -C "$migration_repository" rev-parse HEAD)" ]]
[[ $(< "$state_dir/installed-version") == "$(< "$repository/VERSION")" ]]
[[ $(< "$state_dir/installed-release-tag") == unreleased ]]
[[ -f "$state_dir/migrations-applied" ]]
[[ ! -e "$test_root/cache/hyprarch/git-prs.json" ]]
[[ ! -e "$test_root/cache/hyprarch/git-login" ]]

printf 'CLI and migration smoke tests passed.\n'
# The shared login hook is installed alongside console autologin.
# shellcheck disable=SC2016
grep -Fq '"$REPO_DIR/scripts/configure-session-profile.sh"' "$repository/install.sh"
"$repository/tests/configure-session-profile.sh" < /dev/null

# Exercise only bootstrap's existing-checkout handoff in a disposable checkout;
# the real bootstrap (and its host prerequisites) is never run.
bootstrap_home=$test_root/bootstrap-home
bootstrap_repository=$bootstrap_home/.local/share/blankweave/repository
mkdir -p "$bootstrap_repository/.git" "$bootstrap_repository/bin" "$test_root/bootstrap-bin"
cat > "$bootstrap_repository/bin/blankweave" <<'EOF_FIXTURE'
#!/bin/sh
printf '%s\n' "$1" > "$BOOTSTRAP_CALL"
EOF_FIXTURE
cat > "$test_root/bootstrap-bin/git" <<'EOF_FIXTURE'
#!/bin/sh
printf 'https://github.com/shivamx96/blankweave.git\n'
EOF_FIXTURE
chmod +x "$bootstrap_repository/bin/blankweave" "$test_root/bootstrap-bin/git"
# Keep the production branch intact, replacing only terminal input with null.
awk '/^if \[ -e "\$repository" \]; then$/ {copy=1} copy {print} copy && /^fi$/ {exit}' \
    "$repository/bootstrap.sh" | sed 's@</dev/tty@</dev/null@g' > "$test_root/handoff.sh"
for expected in setup update; do
    HOME="$bootstrap_home" XDG_STATE_HOME="$test_root/bootstrap-state" \
        BOOTSTRAP_CALL="$test_root/bootstrap-call" PATH="$test_root/bootstrap-bin:$PATH" \
        sh -c '
            repository=$HOME/.local/share/blankweave/repository
            repository_url=https://github.com/shivamx96/blankweave.git
            repository_url_no_suffix=https://github.com/shivamx96/blankweave
            repository_ssh_url=git@github.com:shivamx96/blankweave.git
            repository_ssh_url_no_suffix=git@github.com:shivamx96/blankweave
            die() { exit 1; }
            . "$1"
        ' sh "$test_root/handoff.sh"
    [[ $(cat "$test_root/bootstrap-call") == "$expected" ]]
    mkdir -p "$test_root/bootstrap-state/blankweave"
    printf 'recorded-revision\n' > "$test_root/bootstrap-state/blankweave/installed-revision"
done

release_fixture=$test_root/bootstrap-release
git init --quiet --initial-branch=main "$release_fixture"
git -C "$release_fixture" config user.name Fixture
git -C "$release_fixture" config user.email fixture@example.invalid
mkdir -p "$release_fixture/scripts"
cp "$repository/scripts/verify-release.sh" "$repository/scripts/release-version.sh" "$release_fixture/scripts/"
printf '0.9.0\n' > "$release_fixture/VERSION"
git -C "$release_fixture" add .
git -C "$release_fixture" commit --quiet -m release
git -C "$release_fixture" tag -a v0.9.0 -m release
printf '0.10.0\n' > "$release_fixture/VERSION"
git -C "$release_fixture" commit --quiet -am release
git -C "$release_fixture" tag -a v0.10.0 -m release
release_revision=$(git -C "$release_fixture" rev-parse HEAD)
printf 'unreleased\n' > "$release_fixture/work"
git -C "$release_fixture" add .
git -C "$release_fixture" commit --quiet -m development
git -C "$release_fixture" update-ref refs/remotes/origin/main HEAD
awk '/^release_tag=/ {copy=1} copy && /^mv / {exit} copy {print}' \
    "$repository/bootstrap.sh" > "$test_root/select-release.sh"
sh -c 'temporary_repository=$1; die() { exit 1; }; . "$2"' sh \
    "$release_fixture" "$test_root/select-release.sh"
[[ $(git -C "$release_fixture" rev-parse HEAD) == "$release_revision" ]]
[[ $(git -C "$release_fixture" branch --show-current) == main ]]
git -C "$release_fixture" tag -d v0.9.0 v0.10.0 >/dev/null
if "$repository/scripts/verify-release.sh" "$release_fixture" --newest > "$test_root/no-release" 2>&1; then exit 1; fi
grep -Fq 'No valid annotated Blankweave release' "$test_root/no-release"

