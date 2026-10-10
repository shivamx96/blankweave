import Quickshell.Services.Pipewire

AudioOutput {
    id: root
    provider: Pipewire
    property PwObjectTracker outputTracker: PwObjectTracker { objects: root.outputNodes }
}
