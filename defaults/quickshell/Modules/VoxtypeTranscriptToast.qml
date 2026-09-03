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
    property bool deliveryCopied: false
    property bool copyConfirmed: false
    readonly property bool focusedScreen: !Hyprland.focusedMonitor
        || modelData.name === Hyprland.focusedMonitor.name

    function copyTranscript() {
        if (root.transcript === "")
            return
        Quickshell.clipboardText = root.transcript
        root.copyConfirmed = true
        hideTimer.interval = 2500
        hideTimer.restart()
    }

    screen: modelData
    visible: open && focusedScreen
    color: "transparent"
    implicitWidth: root.deliveryCopied ? 420 : 220
    implicitHeight: root.deliveryCopied ? 54 : 30
    exclusiveZone: 0
    surfaceFormat.opaque: false

    anchors {
        bottom: true
    }
    margins.bottom: 22

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
            root.deliveryCopied = copied
            root.copyConfirmed = copied
            root.open = root.transcript !== ""
            hideTimer.interval = copied ? 6500 : 2500
            hideTimer.restart()
        }
    }

    Rectangle {
        id: card

        anchors.fill: parent
        radius: root.deliveryCopied ? 12 : 10
        color: cardMouse.containsMouse ? root.theme.surfaceHover : root.theme.panelSurface
        border.width: 1
        border.color: root.theme.outlineStrong

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.deliveryCopied ? 13 : 10
            anchors.rightMargin: 7
            spacing: root.deliveryCopied ? 10 : 7

            Text {
                visible: root.deliveryCopied
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
                    visible: root.deliveryCopied
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
                    text: root.copyConfirmed && !root.deliveryCopied
                        ? "Copied to clipboard"
                        : root.transcript.replace(/\s+/g, " ").trim()
                    color: root.copyConfirmed && !root.deliveryCopied
                        ? root.theme.success
                        : (root.deliveryCopied ? root.theme.textMuted : root.theme.text)
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.deliveryCopied
                        ? root.theme.microTextSize
                        : root.theme.smallTextSize
                    font.weight: root.deliveryCopied ? Font.Normal : Font.Medium
                    renderType: Text.NativeRendering
                }
            }

            Item {
                Layout.preferredWidth: root.deliveryCopied ? 34 : 24
                Layout.preferredHeight: root.deliveryCopied ? 34 : 24

                Text {
                    anchors.centerIn: parent
                    text: root.copyConfirmed ? "󰄬" : "󰆏"
                    color: root.copyConfirmed
                        ? root.theme.success
                        : (cardMouse.containsMouse
                            ? root.theme.accentBright
                            : root.theme.textMuted)
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.iconSize
                    renderType: Text.NativeRendering
                }
            }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.copyTranscript()
        }
    }

    Timer {
        id: hideTimer
        interval: 2500
        onTriggered: root.open = false
    }
}
