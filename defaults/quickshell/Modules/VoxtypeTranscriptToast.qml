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
    implicitWidth: 420
    implicitHeight: 54
    exclusiveZone: 0
    surfaceFormat.opaque: false

    anchors {
        bottom: true
    }
    margins.bottom: 24

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
            hideTimer.restart()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.theme.panelSurface
        border.width: 1
        border.color: root.theme.outlineStrong

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 8
            spacing: 10

            Text {
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
                    Layout.fillWidth: true
                    text: root.copied
                        ? "Copied · focus a text box and paste"
                        : "Text saved · copy if it did not insert"
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
                    color: root.theme.textMuted
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.microTextSize
                    renderType: Text.NativeRendering
                }
            }

            Item {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34

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
        interval: 6500
        onTriggered: root.open = false
    }
}
