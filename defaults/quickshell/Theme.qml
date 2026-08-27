import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool dark: true

    readonly property color canvas: dark ? "#05080f" : "#edf4ff"
    readonly property color barSurface: dark ? "#c7070b12" : "#d9f8fbff"
    readonly property color surface: dark ? "#e60a101b" : "#f5ffffff"
    readonly property color surfaceRaised: dark ? "#f0111a2a" : "#fff7fbff"
    readonly property color surfaceHover: dark ? "#182944" : "#e3efff"
    readonly property color surfacePressed: dark ? "#213b62" : "#cfe3ff"
    readonly property color text: dark ? "#f4f8ff" : "#081426"
    readonly property color textMuted: dark ? "#8798ae" : "#607087"
    readonly property color accent: dark ? "#3b82f6" : "#2563eb"
    readonly property color accentBright: dark ? "#67a6ff" : "#1d4ed8"
    readonly property color accentSurface: dark ? "#253b82f6" : "#1f2563eb"
    readonly property color outline: dark ? "#33476a" : "#bdd3f3"
    readonly property color outlineStrong: dark ? "#4f75ad" : "#8ab4ed"
    readonly property color divider: dark ? "#253b587a" : "#b4cbe9"
    readonly property color success: dark ? "#3ddc97" : "#07894f"
    readonly property color warning: dark ? "#f4bf50" : "#b46608"
    readonly property color critical: dark ? "#ff6b8a" : "#d52149"

    readonly property string fontFamily: "Inter"
    readonly property string monoFontFamily: "JetBrainsMono Nerd Font"
    readonly property string iconFontFamily: "JetBrainsMono Nerd Font"

    readonly property int barHeight: 42
    readonly property int widgetHeight: 30
    readonly property int widgetRadius: 4
    readonly property int sectionPadding: 10
    readonly property int widgetPadding: 9
    readonly property int gap: 6

    function applyTheme(value) {
        root.dark = String(value || "").trim() !== "light"
    }

    property FileView stateFile: FileView {
        path: Quickshell.env("HOME") + "/.local/share/hyprarch/theme"
        watchChanges: true
        printErrors: false
        onLoaded: root.applyTheme(text())
        onFileChanged: reload()
        onLoadFailed: root.dark = true
    }
}
