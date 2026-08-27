import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../Components"

WidgetFrame {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: !sink || !sink.audio || sink.audio.muted
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property int percentage: Math.round(volume * 100)
    readonly property var sinks: {
        const values = Pipewire.nodes ? Pipewire.nodes.values : []
        const available = []
        for (let index = 0; index < values.length; index++) {
            const node = values[index]
            if (node && node.isSink && !node.isStream)
                available.push(node)
        }
        return available.sort((left, right) => root.nodeLabel(left).localeCompare(root.nodeLabel(right)))
    }

    function nodeLabel(node) {
        if (!node)
            return "Unknown output"
        return String(node.description || node.nickname || node.name || "Audio output")
    }

    function setPreferredSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node
    }

    visible: sink !== null
    icon: muted ? "󰝟" : (percentage < 35 ? "󰕿" : (percentage < 70 ? "󰖀" : "󰕾"))
    label: muted ? "Muted" : percentage + "%"
    tooltip: (sink ? root.nodeLabel(sink) : "No audio output")
        + "\nClick for controls · Scroll to adjust · Right-click to mute"
    attention: muted

    PwObjectTracker {
        objects: root.sinks
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            bar.hideTooltip(root)
            audioPanel.open = !audioPanel.open
        }
        else if (button === Qt.RightButton && sink && sink.audio)
            sink.audio.muted = !sink.audio.muted
    }

    onScrolled: delta => {
        if (!sink || !sink.audio)
            return

        sink.audio.volume = Math.max(0, Math.min(1.5, volume + (delta > 0 ? 0.02 : -0.02)))
    }

    ControlPopup {
        id: audioPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 370

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "󰕾"
                color: root.theme.accentBright
                font.family: root.theme.iconFontFamily
                font.pixelSize: root.theme.heroIconSize
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "AUDIO OUTPUT"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.textSize
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }

                Text {
                    Layout.fillWidth: true
                    text: root.nodeLabel(root.sink)
                    color: root.theme.textMuted
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                }
            }

            Item {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 28

                Text {
                    anchors.centerIn: parent
                    text: root.muted ? "󰝟" : "󰕾"
                    color: root.muted ? root.theme.critical : root.theme.text
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.controlIconSize
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: muteMouse.containsMouse ? 18 : 0
                    height: 1
                    color: root.muted ? root.theme.critical : root.theme.accentBright

                    Behavior on width {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    id: muteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.sink && root.sink.audio)
                            root.sink.audio.muted = !root.sink.audio.muted
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: root.muted ? "󰝟" : (root.percentage < 35 ? "󰕿" : (root.percentage < 70 ? "󰖀" : "󰕾"))
                color: root.muted ? root.theme.critical : root.theme.accentBright
                font.family: root.theme.iconFontFamily
                font.pixelSize: root.theme.controlIconSize
            }

            ControlSlider {
                theme: root.theme
                Layout.fillWidth: true
                from: 0
                to: 1.5
                value: root.volume
                stepSize: 0.01
                onMoved: {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.volume = value
                }
            }

            Text {
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignRight
                text: root.percentage + "%"
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.theme.divider
        }

        Text {
            text: "OUTPUT DEVICES"
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            font.weight: Font.DemiBold
            font.letterSpacing: 1.1
        }

        ListView {
            id: sinkList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 200)
            model: root.sinks
            spacing: 0
            clip: true
            interactive: contentHeight > height

            delegate: Item {
                id: sinkRow

                required property var modelData
                readonly property bool selected: root.sink === modelData

                width: sinkList.width
                height: 38

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
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: selectedMark.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.nodeLabel(sinkRow.modelData)
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
                    onClicked: root.setPreferredSink(sinkRow.modelData)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 30

            RowLayout {
                anchors.centerIn: parent
                spacing: 7

                Text {
                    text: "󰒓"
                    color: root.theme.accentBright
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.iconSize
                }

                Text {
                    text: "Open advanced mixer"
                    color: root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                    font.weight: Font.Medium
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: mixerMouse.containsMouse ? 122 : 0
                height: 1
                color: root.theme.accentBright

                Behavior on width {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: mixerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.bar.run(["pavucontrol"])
            }
        }
    }

}
