pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"

WidgetFrame {
    id: root

    readonly property var audio: bar.shell.audio
    readonly property bool muted: !audio.available || audio.muted
    readonly property int percentage: Math.round(audio.volume * 100)

    visible: audio.outputKey !== ""
    icon: muted ? "󰝟" : (percentage < 35 ? "󰕿" : (percentage < 70 ? "󰖀" : "󰕾"))
    iconPixelSize: theme.barIconSize + 3
    label: muted ? "Muted" : percentage + "%"
    tooltip: audio.outputLabel
        + "\nClick for controls · Scroll to adjust · Right-click to mute"
    attention: muted

    onPressed: button => {
        if (button === Qt.LeftButton) {
            bar.hideTooltip(root)
            audioPanel.open = !audioPanel.open
        }
        else if (button === Qt.RightButton)
            audio.setOutputMuted(!audio.muted)
    }

    onScrolled: delta => audio.setOutputVolume(audio.volume + (delta > 0 ? 0.02 : -0.02))

    ControlPopup {
        id: audioPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 350

        ControlPanelHeader {
            theme: root.theme
            icon: "󰎆"
            title: "SOUND"
            subtitle: root.audio.outputLabel
            actions: [
                { "id": "mixer", "icon": "󰒓" },
                { "id": "mute", "icon": root.muted ? "󰝟" : "󰕾", "attention": root.muted }
            ]
            onActionPressed: actionId => {
                if (actionId === "mixer") {
                    audioPanel.open = false
                    root.bar.run(["pavucontrol"])
                }
                else if (actionId === "mute")
                    root.audio.setOutputMuted(!root.audio.muted)
            }
        }

        ControlSectionLabel {
            theme: root.theme
            text: "OUTPUT LEVEL"
        }

        AudioVolumeControl {
            theme: root.theme
            backend: root.audio
        }

        ControlDivider { theme: root.theme }

        ControlSectionLabel {
            theme: root.theme
            text: "OUTPUT DEVICES"
        }

        ListView {
            id: sinkList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 200)
            model: root.audio.outputs
            spacing: 0
            clip: true
            interactive: contentHeight > height

            delegate: Item {
                id: sinkRow

                required property var modelData
                readonly property bool selected: root.audio.outputKey === modelData.key

                width: sinkList.width
                height: 36

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: sinkRow.selected ? 20 : (sinkMouse.containsMouse ? 12 : 0)
                    color: root.theme.accentBright

                    Behavior on height {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }

                Text {
                    id: deviceIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.audio.icon(sinkRow.modelData.label)
                    color: sinkRow.selected ? root.theme.accentBright : root.theme.textMuted
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.iconSize
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.left: deviceIcon.right
                    anchors.leftMargin: 10
                    anchors.right: selectedMark.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: sinkRow.modelData.label
                    textFormat: Text.PlainText
                    color: sinkRow.selected ? root.theme.accentBright : root.theme.text
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                    font.weight: sinkRow.selected ? Font.DemiBold : Font.Normal
                }

                Text {
                    id: selectedMark
                    visible: sinkRow.selected
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰄬"
                    color: root.theme.accentBright
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.iconSize
                }

                MouseArea {
                    id: sinkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.audio.selectOutput(sinkRow.modelData.key)
                }
            }
        }

    }

}
