import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../Components"
import "../Modules"

PanelWindow {
    id: root

    required property var modelData
    required property var theme
    required property var shell

    property Item tooltipTarget: null
    property Item pendingTooltipTarget: null
    property string tooltipText: ""
    property string pendingTooltipText: ""
    property bool revealHeld: false
    property var visibilityHolds: []
    readonly property bool compact: width < 1700
    readonly property bool veryCompact: width < 1250
    readonly property var preferences: root.shell.preferences.bar
    readonly property string position: String(preferences.position) === "bottom" ? "bottom" : "top"
    readonly property bool atBottom: position === "bottom"
    readonly property string visibilityMode: {
        const requested = String(preferences.visibilityMode)
        return requested === "auto-hide" || requested === "fullscreen"
            ? requested
            : "always"
    }
    readonly property var hyprlandMonitor: Hyprland.monitorFor(root.modelData)
    readonly property bool fullscreenHere: Boolean(hyprlandMonitor
        && hyprlandMonitor.activeWorkspace
        && hyprlandMonitor.activeWorkspace.hasFullscreen)
    readonly property bool concealable: visibilityMode === "auto-hide"
        || (visibilityMode === "fullscreen" && fullscreenHere)
    readonly property bool popupHeld: visibilityHolds.length > 0
    readonly property bool barShown: !concealable || revealHeld || popupHeld || barHover.hovered
    readonly property int revealThickness: 2

    screen: modelData
    color: "transparent"
    implicitHeight: theme.barHeight
    exclusiveZone: visibilityMode === "auto-hide"
        || (visibilityMode === "fullscreen" && fullscreenHere)
        ? 0
        : theme.barHeight
    mask: Region { item: barContent }
    surfaceFormat.opaque: false

    anchors {
        top: !root.atBottom
        bottom: root.atBottom
        left: true
        right: true
    }

    WlrLayershell.namespace: "blankweave-bar"
    // Hyprland suppresses Top layers behind fullscreen clients. Overlay keeps
    // "always" honest and makes the concealed edge reachable in hide modes.
    WlrLayershell.layer: root.fullscreenHere ? WlrLayer.Overlay : WlrLayer.Top

    function setVisibilityHold(owner, held) {
        const next = []
        for (let index = 0; index < root.visibilityHolds.length; index++) {
            if (root.visibilityHolds[index] !== owner)
                next.push(root.visibilityHolds[index])
        }
        if (held)
            next.push(owner)
        root.visibilityHolds = next

        if (held)
            concealTimer.stop()
        else
            root.scheduleConceal()
    }

    function scheduleConceal() {
        if (!root.concealable) {
            root.revealHeld = false
            concealTimer.stop()
        }
        else if (!barHover.hovered && !root.popupHeld)
            concealTimer.restart()
    }

    onConcealableChanged: scheduleConceal()

    function run(command) {
        Quickshell.execDetached(command)
    }

    function showTooltip(target, text) {
        pendingTooltipTarget = target
        pendingTooltipText = String(text || "")
        tooltipTimer.restart()
    }

    function hideTooltip(target) {
        if (pendingTooltipTarget === target) {
            pendingTooltipTarget = null
            pendingTooltipText = ""
            tooltipTimer.stop()
        }
        if (tooltipTarget === target) {
            tooltipTarget = null
            tooltipText = ""
        }
    }

    Timer {
        id: concealTimer
        interval: 650
        onTriggered: {
            if (!barHover.hovered && !root.popupHeld)
                root.revealHeld = false
        }
    }

    Item {
        id: barContent

        x: 0
        y: root.barShown
            ? 0
            : (root.atBottom
                ? root.theme.barHeight - root.revealThickness
                : -root.theme.barHeight + root.revealThickness)
        width: parent.width
        height: parent.height

        Behavior on y {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: barHover

            onHoveredChanged: {
                if (hovered) {
                    root.revealHeld = true
                    concealTimer.stop()
                }
                else {
                    root.scheduleConceal()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: root.theme.barSurface

            Rectangle {
                x: 0
                y: root.atBottom ? parent.height - height : 0
                width: parent.width
                height: 1
                color: root.theme.barHighlight
            }

            Rectangle {
                x: 0
                y: root.atBottom ? 0 : parent.height - height
                width: parent.width
                height: 1
                color: root.theme.outline
            }

            Rectangle {
                x: Math.round((parent.width - width) / 2)
                y: root.atBottom ? 0 : parent.height - height
                width: Math.min(parent.width * 0.28, 560)
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: root.theme.accentBright }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }

        Timer {
            id: tooltipTimer
            interval: 420
            onTriggered: {
                root.tooltipTarget = root.pendingTooltipTarget
                root.tooltipText = root.pendingTooltipText
            }
        }

        BarSection {
            id: leftIsland
            theme: root.theme
            anchors.left: parent.left
            anchors.leftMargin: root.theme.sectionPadding
            anchors.verticalCenter: parent.verticalCenter

            SystemOverviewWidget { bar: root; theme: root.theme }
            BarDivider { theme: root.theme }
            WorkspacesWidget { bar: root; theme: root.theme }
            BarDivider { theme: root.theme; visible: !root.veryCompact }
            ActiveWindowWidget { bar: root; theme: root.theme; visible: !root.veryCompact }
        }

        BarSection {
            id: centerIsland
            theme: root.theme
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            z: 2

            ClockWidget { bar: root; theme: root.theme }
        }

        BarSection {
            theme: root.theme
            anchors.right: centerIsland.left
            anchors.verticalCenter: parent.verticalCenter
            z: 2

            WeatherWidget { bar: root; theme: root.theme }
        }

        BarSection {
            id: rightIsland
            theme: root.theme
            anchors.right: parent.right
            anchors.rightMargin: root.theme.sectionPadding
            anchors.verticalCenter: parent.verticalCenter

            ApplicationIndicatorsWidget {
                id: applicationIndicators
                bar: root
                theme: root.theme
            }
            BarDivider { theme: root.theme; visible: applicationIndicators.hasIndicators }

            BrightnessWidget { bar: root; theme: root.theme; iconOnly: true }
            AudioWidget { bar: root; theme: root.theme; iconOnly: true }
            BluetoothWidget { bar: root; theme: root.theme; iconOnly: true }
            NetworkWidget { bar: root; theme: root.theme; iconOnly: true }
            NotificationWidget { bar: root; theme: root.theme }
            BatteryWidget { bar: root; theme: root.theme; iconOnly: true }
            BarDivider { theme: root.theme }

            MemoryWidget {
                bar: root
                theme: root.theme
                iconOnly: root.compact
            }

            CpuWidget {
                bar: root
                theme: root.theme
                iconOnly: root.compact
            }

            GpuWidget {
                bar: root
                theme: root.theme
                iconOnly: root.compact
            }

            PowerWidget { bar: root; theme: root.theme }
        }
    }

    PopupWindow {
        id: tooltipWindow

        visible: root.tooltipTarget !== null && root.tooltipText !== ""
        color: "transparent"
        implicitWidth: Math.min(420, tooltipLabel.implicitWidth + 24)
        implicitHeight: tooltipLabel.implicitHeight + 18

        anchor {
            id: tooltipAnchor
            window: root
            adjustment: PopupAdjustment.Slide
            edges: root.atBottom
                ? (Edges.Bottom | Edges.Left)
                : (Edges.Top | Edges.Left)
            gravity: root.atBottom
                ? (Edges.Top | Edges.Right)
                : (Edges.Bottom | Edges.Right)
            rect.width: 1
            rect.height: 1

            onAnchoring: {
                const target = root.tooltipTarget
                if (!target)
                    return

                const targetY = root.atBottom ? 0 : target.height + 7
                const point = root.contentItem.mapFromItem(
                    target,
                    target.width / 2 - tooltipWindow.implicitWidth / 2,
                    targetY
                )
                tooltipAnchor.rect.x = Math.round(Math.max(4, Math.min(point.x, root.width - tooltipWindow.implicitWidth - 4)))
                tooltipAnchor.rect.y = Math.round(point.y)
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.theme.widgetRadius
            color: root.theme.surfaceRaised
            border.width: 1
            border.color: root.theme.outlineStrong

            Text {
                id: tooltipLabel
                anchors.centerIn: parent
                width: Math.min(396, implicitWidth)
                text: root.tooltipText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                lineHeight: 1.2
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }
        }
    }
}
