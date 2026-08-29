import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../Components"

WidgetFrame {
    id: root

    readonly property var activeWindow: Hyprland.activeToplevel
    readonly property string windowTitle: activeWindow && activeWindow.title
        ? String(activeWindow.title)
        : "Desktop"
    // Wayland reports the app id a desktop entry can be looked up by; the
    // Hyprland window class is the fallback for XWayland clients.
    readonly property string appId: {
        if (!activeWindow)
            return ""
        if (activeWindow.wayland && activeWindow.wayland.appId)
            return String(activeWindow.wayland.appId)
        if (activeWindow.lastIpcObject && activeWindow.lastIpcObject.class)
            return String(activeWindow.lastIpcObject.class)
        return ""
    }
    readonly property var appEntry: root.appId
        ? (DesktopEntries.byId(root.appId) || DesktopEntries.heuristicLookup(root.appId))
        : null
    // Falls back to the generic window glyph whenever nothing resolves, so an
    // unpackaged or misreported client never leaves a hole in the bar.
    readonly property url appIcon: {
        if (root.appEntry && root.appEntry.icon)
            return Quickshell.iconPath(String(root.appEntry.icon), true)
        if (root.appId)
            return Quickshell.iconPath(root.appId.toLowerCase(), true)
        return ""
    }

    icon: activeWindow ? "󰖯" : "󰇄"
    iconPixelSize: theme.barIconSize + 4
    iconImage: root.appIcon
    label: windowTitle.length > 34 ? windowTitle.slice(0, 33) + "…" : windowTitle
    tooltip: activeWindow
        ? (root.appEntry && root.appEntry.name
            ? String(root.appEntry.name) + "\n" + windowTitle
            : windowTitle)
        : "No active window"
    horizontalPadding: 10
}
