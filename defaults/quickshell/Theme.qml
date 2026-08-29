import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // The palette is resolved by theme-apply.sh into ~/.config/hyprarch/theme.json,
    // the only file it is read from. Until the first apply has run, the bundled
    // default theme's dark mode stands in so the shell never draws unthemed.
    readonly property string configDirectory: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")) + "/hyprarch"
    readonly property string bundledDefault: Quickshell.env("HOME")
        + "/.local/share/hyprarch/themes/obsidian/theme.json"

    property var resolved: null
    property var fallback: null
    readonly property var palette: (resolved && resolved.colors)
        || (fallback && fallback.colors)
        || ({})

    readonly property string themeId: resolved ? String(resolved.theme || "obsidian") : "obsidian"
    readonly property string mode: resolved ? String(resolved.mode || "dark") : "dark"
    readonly property bool dark: mode !== "light"

    // Theme files use CSS #rrggbb[aa]; Qt reads a nine-digit literal as
    // #aarrggbb. Magenta is deliberately loud: theme-apply.sh validates every
    // token, so a hole here means both theme files failed to load.
    function cssColor(value) {
        value = String(value || "")
        if (/^#[0-9a-fA-F]{6}$/.test(value))
            return value
        if (/^#[0-9a-fA-F]{8}$/.test(value))
            return "#" + value.slice(7, 9) + value.slice(1, 7)
        return "#ff00ff"
    }

    function token(name) {
        return cssColor(palette[name])
    }

    readonly property color canvas: token("canvas")
    readonly property color barSurface: token("barSurface")
    readonly property color barHighlight: token("barHighlight")
    readonly property color panelSurface: token("panelSurface")
    readonly property color surface: token("surface")
    readonly property color surfaceRaised: token("surfaceRaised")
    readonly property color surfaceHover: token("surfaceHover")
    readonly property color surfacePressed: token("surfacePressed")
    readonly property color scrim: token("scrim")
    readonly property color text: token("text")
    readonly property color textMuted: token("textMuted")
    readonly property color accent: token("accent")
    readonly property color accentBright: token("accentBright")
    readonly property color accentSurface: token("accentSurface")
    readonly property color outline: token("outline")
    readonly property color outlineStrong: token("outlineStrong")
    readonly property color divider: token("divider")
    readonly property color success: token("success")
    readonly property color warning: token("warning")
    readonly property color critical: token("critical")

    readonly property string fontFamily: "Atkinson Hyperlegible Next"
    readonly property string monoFontFamily: "JetBrainsMono Nerd Font"
    readonly property string iconFontFamily: "JetBrainsMono Nerd Font"

    readonly property int textSize: 13
    readonly property int smallTextSize: 12
    readonly property int microTextSize: 11
    readonly property int iconSize: 15
    // The bar's optical target: a Nerd Font glyph fills roughly 7/8 of its em
    // box and a vector mark 5/6 of its keyline, so 18 here and 19 for a mark
    // both land on ~15.8px of ink. Widgets whose glyph deviates from that fill
    // correct with iconPixelSize rather than moving this.
    readonly property int barIconSize: 18
    readonly property int controlIconSize: 17
    readonly property int heroIconSize: 21

    readonly property int barHeight: 40
    readonly property int widgetHeight: 30
    readonly property int widgetRadius: 4
    readonly property int sectionPadding: 7
    readonly property int widgetPadding: 6
    readonly property int metricLabelWidth: 32
    readonly property int widgetContentGap: 4
    readonly property int barItemGap: 0
    readonly property int dividerMargin: 5

    function parse(text) {
        try {
            return JSON.parse(text)
        } catch (error) {
            return null
        }
    }

    // theme-apply.sh rewrites the state in place, so a read that lands
    // mid-write can be empty; keep the last good palette rather than flashing
    // the fallback until the next change notification.
    property FileView stateFile: FileView {
        path: root.configDirectory + "/theme.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const next = root.parse(text())
            if (next && next.colors)
                root.resolved = next
        }
        onFileChanged: reload()
    }

    property FileView fallbackFile: FileView {
        path: root.bundledDefault
        printErrors: false
        onLoaded: {
            const theme = root.parse(text())
            root.fallback = theme && theme.modes ? theme.modes.dark : null
        }
    }
}
