import QtQuick

// The native adapter supplies PipeWire; tests supply an isolated object model.
QtObject {
    id: root
    required property var provider
    readonly property bool ready: Boolean(provider && provider.ready)
    readonly property var inputNodes: {
        const nodes = provider && provider.nodes ? provider.nodes.values : []
        return nodes.filter(node => node && !node.isSink && !node.isStream && node.audio)
    }
    // Delegates retain only primitives. Resolve a fresh node for every action,
    // since removal can destroy the native wrapper while a menu is open.
    readonly property var inputs: inputNodes.map(node => ({key: key(node), label: label(node)}))
        .sort((left, right) => left.label.localeCompare(right.label) || left.key.localeCompare(right.key))
    readonly property var input: ready && inputNodes.includes(provider.defaultAudioSource) ? provider.defaultAudioSource : null
    readonly property string inputKey: key(input)
    readonly property string inputLabel: input ? label(input) : "No audio input"
    readonly property bool available: Boolean(input && input.audio && input.audio.volumes.length > 0
        && Number.isFinite(input.audio.volume))
    readonly property real volume: available ? input.audio.volume : 0
    readonly property bool muted: !available || input.audio.muted
    readonly property string preferredKey: ready ? key(provider.preferredDefaultAudioSource) : ""
    readonly property string notice: !ready ? "Connecting to the audio service…"
        : inputs.length === 0 ? "No audio inputs detected. Connect a microphone."
        : !input ? "Choose an input device to record audio."
        : !available ? "Reading input volume…"
        : preferredKey && preferredKey !== inputKey
            ? "Preferred: " + label(provider.preferredDefaultAudioSource) + ". Currently using " + inputLabel + "."
        : "Using " + inputLabel + "."
    // The native adapter supplies a monitor; tests use a deterministic signal.
    property var monitor: null
    property bool active: false
    readonly property var monitorNode: active && available && !muted ? input : null
    readonly property bool levelReady: Boolean(monitorNode && monitor && monitor.node === input
        && monitor.channels.length > 0)
    readonly property real level: levelReady && Number.isFinite(monitor.peak)
        ? Math.max(0, Math.min(1, monitor.peak)) : 0
    readonly property string levelNotice: !available ? "Microphone signal unavailable"
        : muted ? "Microphone muted"
        : !active ? "Meter paused"
        : !levelReady ? "Waiting for microphone signal…"
        : "Signal level (before software gain)"
    property int generation: 0
    onInputChanged: generation++
    onReadyChanged: generation++
    onAvailableChanged: if (!available) generation++

    function key(node) { return node ? String(node.id) + ":" + node.name : "" }
    function label(node) { return node ? String(node.description || node.nickname || node.name || "Audio input") : "Unknown input" }
    function selectInput(key) {
        if (!ready) return
        const node = inputNodes.find(candidate => root.key(candidate) === key)
        if (node) provider.preferredDefaultAudioSource = node
    }
    function setVolume(value, expectedGeneration = generation) {
        if (!available || expectedGeneration !== generation || !Number.isFinite(value)) return
        input.audio.volume = Math.max(0, Math.min(1.5, value))
    }
    function setInputMuted(value, expectedGeneration = generation) {
        if (available && expectedGeneration === generation && typeof value === "boolean") input.audio.muted = value
    }
}
