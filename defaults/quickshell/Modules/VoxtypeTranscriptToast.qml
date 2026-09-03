import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var modelData
    required property var theme
    required property var voice
    property bool open: false
    property string transcript: ""
    property bool copied: false
    readonly property bool focusedScreen: !Hyprland.focusedMonitor
        || modelData.name === Hyprland.focusedMonitor.name

    screen: modelData
    visible: open && focusedScreen
    color: "transparent"
    implicitWidth: root.copied ? 420 : 220
    implicitHeight: root.copied ? 54 : 30
    exclusiveZone: 0
    surfaceFormat.opaque: false

    anchors {
        bottom: true
    }
    margins.bottom: root.copied ? 24 : 18

    WlrLayershell.namespace: "blankweave-voxtype-transcript"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Connections {
        target: root.voice

        function onTranscriptAvailable(text, copied) {
            if (!root.focusedScreen)
                return
            root.transcript = String(text || "")
            root.copied = copied
            root.open = root.transcript !== ""
            hideTimer.interval = copied ? 6500 : 2200
            hideTimer.restart()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.copied ? 12 : 10
        color: root.theme.panelSurface
        border.width: 1
        border.color: root.theme.outlineStrong

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.copied ? 13 : 10
            anchors.rightMargin: 7
            spacing: root.copied ? 10 : 7

            Text {
                visible: root.copied
                text: "󰅍"
                color: root.theme.accentBright
                font.family: root.theme.iconFontFamily
                font.pixelSize: root.theme.controlIconSize
                renderType: Text.NativeRendering
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    visible: root.copied
                    Layout.fillWidth: true
                    text: "Copied · focus a text box and paste"
                    color: root.theme.text
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    Layout.fillWidth: true
                    text: root.transcript.replace(/\s+/g, " ").trim()
                    color: root.copied ? root.theme.textMuted : root.theme.text
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.copied
                        ? root.theme.microTextSize
                        : root.theme.smallTextSize
                    font.weight: root.copied ? Font.Normal : Font.Medium
                    renderType: Text.NativeRendering
                }
            }

            Item {
                Layout.preferredWidth: root.copied ? 34 : 24
                Layout.preferredHeight: root.copied ? 34 : 24

                Text {
                    anchors.centerIn: parent
                    text: "󰆏"
                    color: root.theme.textMuted
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.iconSize
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.clipboardText = root.transcript
                        root.copied = true
                        root.open = false
                    }
                }
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 2200
        onTriggered: root.open = false
    }
}
