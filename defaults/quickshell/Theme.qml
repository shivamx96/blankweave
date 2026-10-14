import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // The palette is resolved by theme-apply.sh into ~/.config/blankweave/theme.json,
    // the only file it is read from. Until the first apply has run, the bundled
    // default theme's dark mode stands in so the shell never draws unthemed.
    readonly property string configDirectory: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")) + "/blankweave"
    readonly property string bundledDefault: Quickshell.env("HOME")
        + "/.local/share/blankweave/themes/obsidian/theme.json"

    property var resolved: null
    property var fallback: null
    readonly property var basePalette: (resolved && resolved.colors)
        || (fallback && fallback.colors)
        || ({})

    readonly property var palette: highContrast ? (dark ? contrastDark : contrastLight) : basePalette
    readonly property var contrastDark: ({
        canvas: "#000000", barSurface: "#000000", barHighlight: "#202020", panelSurface: "#000000",
        surface: "#000000", surfaceRaised: "#101010", surfaceHover: "#242424", surfacePressed: "#202020",
        scrim: "#000000cc", text: "#ffffff", textMuted: "#eeeeee", accent: "#8ac7ff", accentBright: "#8ac7ff",
        accentSurface: "#152536", outline: "#b0b0b0", outlineStrong: "#ffffff", divider: "#b0b0b0",
        success: "#7aefad", warning: "#ffdb70", critical: "#ff9c9c"
    })
    readonly property var contrastLight: ({
        canvas: "#ffffff", barSurface: "#ffffff", barHighlight: "#e8e8e8", panelSurface: "#ffffff",
        surface: "#ffffff", surfaceRaised: "#f5f5f5", surfaceHover: "#dedede", surfacePressed: "#e8e8e8",
        scrim: "#000000cc", text: "#000000", textMuted: "#202020", accent: "#003a80", accentBright: "#003a80",
        accentSurface: "#d6e8ff", outline: "#4a4a4a", outlineStrong: "#000000", divider: "#4a4a4a",
        success: "#005626", warning: "#6b4800", critical: "#a00000"
    })
    property bool reducedMotion: false
    property bool highContrast: false
    property FileView accessibilityFile: FileView {
        path: root.configDirectory + "/accessibility.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const next = root.parse(text())
            if (next && next.version === 1 && typeof next.reduced_motion === "boolean" && typeof next.high_contrast === "boolean") {
                root.reducedMotion = next.reduced_motion
                root.highContrast = next.high_contrast
            }
        }
        onLoadFailed: { root.reducedMotion = false; root.highContrast = false }
        onFileChanged: reload()
    }

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

    property real textScale: 1.0
    property FileView interfaceFile: FileView {
        path: root.configDirectory + "/interface.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const next = root.parse(text())
            if (next && next.version === 1 && [1, 1.15, 1.3].includes(next.text_scale))
                root.textScale = next.text_scale
        }
        onLoadFailed: root.textScale = 1.0
        onFileChanged: reload()
    }

    readonly property int textSize: Math.round(13 * textScale)
    readonly property int smallTextSize: Math.round(12 * textScale)
    readonly property int microTextSize: Math.round(11 * textScale)
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
    // Panels hang below the bar as separate surfaces, so they take the same
    // gentle curve as the compositor's windows rather than the bar's tighter one.
    readonly property int panelRadius: 14
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
