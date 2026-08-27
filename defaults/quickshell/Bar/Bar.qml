import QtQuick
import QtQuick.Layouts
import Quickshell
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
    readonly property bool compact: width < 1700
    readonly property bool veryCompact: width < 1250

    screen: modelData
    color: "transparent"
    implicitHeight: theme.barHeight
    exclusiveZone: theme.barHeight
    surfaceFormat.opaque: false

    anchors {
        top: true
        left: true
        right: true
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.barSurface

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: root.theme.dark ? "#18ffffff" : "#70ffffff"
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: root.theme.outline
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
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

    WlrLayershell.namespace: "hyprarch-bar"
    WlrLayershell.layer: WlrLayer.Top

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

        ApplicationLauncherWidget { bar: root; theme: root.theme }
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
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1

            onAnchoring: {
                const target = root.tooltipTarget
                if (!target)
                    return

                const point = root.contentItem.mapFromItem(
                    target,
                    target.width / 2 - tooltipWindow.implicitWidth / 2,
                    target.height + 7
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
