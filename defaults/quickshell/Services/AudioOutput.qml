import QtQuick

// The native adapter supplies PipeWire; tests supply an isolated object model.
QtObject {
    id: root
    required property var provider
    readonly property bool ready: Boolean(provider && provider.ready)
    readonly property var outputNodes: {
        const nodes = provider && provider.nodes ? provider.nodes.values : []
        return nodes.filter(node => node && node.isSink && !node.isStream && node.audio)
    }
    // Delegates retain only primitives. Resolve a fresh node for every action,
    // since removal can destroy the native wrapper while a menu is open.
    readonly property var outputs: outputNodes.map(node => ({key: key(node), label: label(node)}))
        .sort((left, right) => left.label.localeCompare(right.label) || left.key.localeCompare(right.key))
    readonly property var output: ready && outputNodes.includes(provider.defaultAudioSink) ? provider.defaultAudioSink : null
    readonly property string outputKey: key(output)
    readonly property string outputLabel: output ? label(output) : "No audio output"
    readonly property bool available: Boolean(output && output.audio && output.audio.volumes.length > 0
        && Number.isFinite(output.audio.volume))
    readonly property real volume: available ? output.audio.volume : 0
    readonly property bool muted: !available || output.audio.muted
    readonly property string preferredKey: ready ? key(provider.preferredDefaultAudioSink) : ""
    readonly property string notice: !ready ? "Connecting to the audio service…"
        : outputs.length === 0 ? "No audio outputs detected. Connect speakers or headphones."
        : !output ? "Choose an output device to start playback."
        : !available ? "Reading output volume…"
        : preferredKey && preferredKey !== outputKey
            ? "Preferred: " + label(provider.preferredDefaultAudioSink) + ". Currently using " + outputLabel + "."
        : "Using " + outputLabel + ". Changes also appear in the bar."
    property int generation: 0
    onOutputChanged: generation++
    onReadyChanged: generation++
    onAvailableChanged: if (!available) generation++

    function key(node) { return node ? String(node.id) + ":" + node.name : "" }
    function label(node) { return node ? String(node.description || node.nickname || node.name || "Audio output") : "Unknown output" }
    function icon(label) {
        const value = label.toLowerCase()
        if (value.includes("headset")) return "󰋎"
        if (value.includes("headphone")) return "󰋋"
        if (value.includes("bluetooth")) return "󰂯"
        if (value.includes("hdmi") || value.includes("displayport") || value.includes("display port")) return "󰍹"
        return "󰓃"
    }
    function selectOutput(key) {
        if (!ready) return
        const node = outputNodes.find(candidate => root.key(candidate) === key)
        if (node) provider.preferredDefaultAudioSink = node
    }
    function setVolume(value, expectedGeneration = generation) {
        if (!available || expectedGeneration !== generation || !Number.isFinite(value)) return
        output.audio.volume = Math.max(0, Math.min(1.5, value))
    }
    function setOutputMuted(value, expectedGeneration = generation) {
        if (available && expectedGeneration === generation && typeof value === "boolean") output.audio.muted = value
    }
}
