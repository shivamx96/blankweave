import QtQuick
import QtQuick.Layouts
import "../Components"

WidgetFrame {
    id: root

    readonly property var voice: root.bar.shell.voxtype
    readonly property bool featureEnabled: voice.featureEnabled
    readonly property bool recording: voice.daemonState === "recording"
    readonly property bool transcribing: voice.daemonState === "transcribing"
    readonly property string stateLabel: recording
        ? "Recording"
        : (transcribing ? "Transcribing" : (voice.available ? "Ready" : "Unavailable"))

    function record(action) {
        // Equivalent to `voxtype record <action>` without invoking a shell.
        root.bar.run(["voxtype", "record", action])
    }

    visible: voice.featureEnabled
    icon: voice.available ? "󰍬" : "󰍭"
    iconOnly: true
    active: dictationPanel.open || transcribing
    attention: recording || (voice.featureEnabled && !voice.available)
    foreground: recording
        ? theme.critical
        : (transcribing ? theme.warning : (dictationPanel.open ? theme.accentBright : theme.text))
    tooltip: !voice.available
        ? "Voice dictation unavailable\nClick for recovery controls"
        : (recording
        ? "Recording · release F12 or click to open controls"
        : (transcribing
        ? "Transcribing locally…"
        : "Voice dictation ready · Super+D or hold F12\nClick for controls"))

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            dictationPanel.open = !dictationPanel.open
        }
        else if (button === Qt.RightButton && voice.available)
            root.record(recording ? "stop" : "start")
    }

    ControlPopup {
        id: dictationPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 350

        ControlPanelHeader {
            theme: root.theme
            icon: root.voice.available ? "󰍬" : "󰍭"
            title: "VOICE DICTATION"
            subtitle: root.recording
                ? "Listening on " + String(root.voice.device || "default")
                : (root.transcribing ? "Processing entirely on this device" : root.stateLabel)
            actions: root.voice.busy
                ? [
                    { "id": "cancel", "icon": "󰜺", "attention": true },
                    { "id": "restart", "icon": "󰑐" }
                ]
                : [
                    { "id": "restart", "icon": "󰑐", "attention": !root.voice.available }
                ]
            onActionPressed: actionId => {
                if (actionId === "cancel")
                    root.record("cancel")
                else if (actionId === "restart") {
                    root.bar.run(["systemctl", "--user", "restart", "voxtype.service"])
                    root.voice.statusSeen = false
                }
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "STATUS",
                    "value": root.stateLabel,
                    "active": root.transcribing,
                    "attention": root.recording || !root.voice.available
                },
                { "label": "MODEL", "value": String(root.voice.model || "—") },
                { "label": "BACKEND", "value": String(root.voice.backend || "—") }
            ]
        }

        ControlAction {
            theme: root.theme
            icon: root.recording ? "󰓛" : "󰍬"
            label: root.recording ? "Stop and transcribe" : "Start dictating"
            active: root.recording
            enabled: root.voice.available && !root.transcribing
            onPressed: root.record(root.recording ? "stop" : "start")
        }

        ControlAction {
            visible: root.voice.busy
            theme: root.theme
            icon: "󰜺"
            label: "Cancel and discard"
            attention: true
            onPressed: root.record("cancel")
        }

        Text {
            Layout.fillWidth: true
            text: "Super+D toggles · hold F12 for push-to-talk"
            color: root.theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }

        Text {
            visible: root.voice.featureEnabled && !root.voice.available
            Layout.fillWidth: true
            text: "The local VoxType service is not responding. Use restart above or run systemctl --user status voxtype."
            color: root.theme.critical
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }
    }
}
