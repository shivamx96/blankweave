import QtQuick

Item {
    id: root

    property string daemonState: "idle"
    property var audio: null
    property var theme: null
    property var recipe: null
    property string assetRoot: ""
    property int transcribingFrame: 0
    readonly property real energy: Math.min(1, Math.max(0,
        (audio ? audio.rms : 0) * 7 + (audio ? audio.peak : 0) * 0.8))
    readonly property var barShape: [0.34, 0.62, 0.9, 0.55, 1.0, 0.68, 0.4]

    function color(role, fallback) {
        return theme && theme.color ? theme.color(role, fallback) : fallback
    }

    function frameColor(key, fallback) {
        const frame = theme && theme.config ? theme.config.frame : null
        return color(frame && frame[key] ? String(frame[key]) : "", fallback)
    }

    function accentColor() {
        const visual = theme && theme.config ? theme.config.visual : null
        const layers = visual && visual.layers ? visual.layers : []
        return color(layers.length > 0 ? String(layers[0].color || "") : "", "#79b8ff")
    }

    Timer {
        interval: 120
        repeat: true
        running: root.daemonState === "transcribing"
        onTriggered: root.transcribingFrame = (root.transcribingFrame + 1) % 7
    }

    Rectangle {
        id: pill

        width: 112
        height: 28
        radius: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        color: root.frameColor("background", "#dd171a20")
        border.width: 1
        border.color: root.frameColor("border", "#805b6472")

        Row {
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: root.barShape

                Rectangle {
                    required property real modelData
                    required property int index
                    width: 3
                    height: root.daemonState === "transcribing"
                        ? (index === root.transcribingFrame ? 15 : (index + 1) % 7 === root.transcribingFrame ? 10 : 5)
                        : 4 + Math.round(15 * root.energy * modelData)
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.accentColor()

                    Behavior on height {
                        NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
