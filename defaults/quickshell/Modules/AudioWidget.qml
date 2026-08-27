import QtQuick
import Quickshell.Services.Pipewire
import "../Components"

WidgetFrame {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: !sink || !sink.audio || sink.audio.muted
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property int percentage: Math.round(volume * 100)

    visible: sink !== null
    icon: muted ? "󰝟" : (percentage < 35 ? "󰕿" : (percentage < 70 ? "󰖀" : "󰕾"))
    label: muted ? "Muted" : percentage + "%"
    tooltip: (sink ? String(sink.description || sink.name || "Default output") : "No audio output")
        + "\nScroll to adjust · Right-click to mute"
    attention: muted

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    onPressed: button => {
        if (button === Qt.LeftButton)
            bar.run(["pavucontrol"])
        else if (button === Qt.RightButton && sink && sink.audio)
            sink.audio.muted = !sink.audio.muted
    }

    onScrolled: delta => {
        if (!sink || !sink.audio)
            return

        sink.audio.volume = Math.max(0, Math.min(1, volume + (delta > 0 ? 0.02 : -0.02)))
    }
}
