import Quickshell.Services.Pipewire

AudioOutput {
    id: root
    provider: Pipewire
    property AudioInput microphone: AudioInput {
        provider: root.provider
        monitor: root.inputMonitor
    }
    property PwObjectTracker inputTracker: PwObjectTracker { objects: root.microphone.inputNodes }
    property PwNodePeakMonitor inputMonitor: PwNodePeakMonitor {
        node: root.microphone.monitorNode
        enabled: node !== null
    }
    property PwObjectTracker outputTracker: PwObjectTracker { objects: root.outputNodes }
}
