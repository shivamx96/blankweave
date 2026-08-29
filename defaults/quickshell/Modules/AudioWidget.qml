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

    function nodeIcon(node) {
        const description = root.nodeLabel(node).toLowerCase()
        if (description.includes("headset"))
            return "󰋎"
        if (description.includes("headphone"))
            return "󰋋"
        if (description.includes("bluetooth"))
            return "󰂯"
        if (description.includes("hdmi") || description.includes("displayport") || description.includes("display port"))
            return "󰍹"
        return "󰓃"
    }

    function setPreferredSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node
    }

    visible: sink !== null
    icon: muted ? "󰝟" : (percentage < 35 ? "󰕿" : (percentage < 70 ? "󰖀" : "󰕾"))
    iconPixelSize: theme.barIconSize + 3
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
        panelWidth: 350

        ControlPanelHeader {
            theme: root.theme
            icon: "󰎆"
            title: "SOUND"
            subtitle: root.nodeLabel(root.sink)
            actions: [
                { "id": "mixer", "icon": "󰒓" },
                { "id": "mute", "icon": root.muted ? "󰝟" : "󰕾", "attention": root.muted }
            ]
            onActionPressed: actionId => {
                if (actionId === "mixer") {
                    audioPanel.open = false
                    root.bar.run(["pavucontrol"])
                }
                else if (actionId === "mute" && root.sink && root.sink.audio)
                    root.sink.audio.muted = !root.sink.audio.muted
            }
        }

        ControlSectionLabel {
            theme: root.theme
            text: "OUTPUT LEVEL"
        }

        ControlValueRow {
            theme: root.theme
            from: 0
            to: 1.5
            value: root.volume
            stepSize: 0.01
            valueText: root.percentage + "%"
            onValueMoved: value => {
                if (root.sink && root.sink.audio)
                    root.sink.audio.volume = value
            }
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
            model: root.sinks
            spacing: 0
            clip: true
            interactive: contentHeight > height

            delegate: Item {
                id: sinkRow

                required property var modelData
                readonly property bool selected: root.sink === modelData

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
                    text: root.nodeIcon(sinkRow.modelData)
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

    }

}
