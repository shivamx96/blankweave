pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool featureEnabled: backend !== null && Boolean(backend.featureEnabled)
    spacing: 12

    Text {
        Layout.fillWidth: true
        objectName: "dictationStatus"
        text: root.backend ? root.backend.stateLabel : "Dictation service unavailable"
        color: root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.textSize
        font.weight: Font.Medium
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: !root.featureEnabled
        text: "Enable the Voice dictation profile with Blankweave setup to install the local speech model and service."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.featureEnabled
        text: root.backend && root.backend.available
            ? "Model: " + root.backend.model + "\nMicrophone: " + (root.backend.device === "default" ? "System default microphone" : root.backend.device)
                + "\nBackend: " + root.backend.backend
            : "Waiting for the dictation service. If it is stopped, use Start service below."
        textFormat: Text.PlainText
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    GridLayout {
        visible: root.featureEnabled
        Layout.fillWidth: true
        columns: root.width < 550 ? 1 : 3
        columnSpacing: 10
        rowSpacing: 10
        SettingsButton {
            objectName: "dictationRecord"
            Layout.fillWidth: true
            theme: root.theme
            text: root.backend && root.backend.daemonState === "recording" ? "Stop and transcribe" : "Record to clipboard"
            enabled: root.backend !== null && (root.backend.canStart || root.backend.canStop)
            onClicked: root.backend.record(root.backend.canStop ? "stop" : "start", true)
        }
        SettingsButton {
            objectName: "dictationCancel"
            Layout.fillWidth: true
            theme: root.theme
            text: "Cancel and discard"
            enabled: root.backend !== null && root.backend.canCancel
            onClicked: root.backend.record("cancel")
        }
        SettingsButton {
            objectName: "dictationRestart"
            Layout.fillWidth: true
            theme: root.theme
            text: root.backend && root.backend.daemonRunning ? "Restart service" : "Start service"
            enabled: root.backend !== null && root.backend.canRestart
            onClicked: root.backend.restart()
        }
    }
    Text {
        Layout.fillWidth: true
        visible: root.backend !== null && root.backend.commandBusy
        text: "Waiting for dictation to confirm the change…"
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        objectName: "dictationError"
        text: root.backend ? root.backend.actionError || root.backend.error : ""
        visible: text !== ""
        textFormat: Text.PlainText
        color: root.theme.critical
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.featureEnabled
        text: "Record here to copy the result to your clipboard. To dictate into another app, focus its text field and use Super+D or hold F12 (default shortcuts)."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.backend !== null && root.backend.hasLastTranscript
        text: "Latest transcript"
        color: root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
    }
    Text {
        Layout.fillWidth: true
        objectName: "dictationTranscript"
        visible: root.backend !== null && root.backend.hasLastTranscript
        text: root.backend ? root.backend.lastTranscript : ""
        textFormat: Text.PlainText
        maximumLineCount: 3
        elide: Text.ElideRight
        wrapMode: Text.WordWrap
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
    }
    SettingsButton {
        objectName: "dictationCopy"
        theme: root.theme
        text: "Copy latest transcript"
        visible: root.backend !== null && root.backend.hasLastTranscript
        enabled: visible
        onClicked: root.backend.copyTranscript()
    }
    Text {
        Layout.fillWidth: true
        visible: root.featureEnabled
        text: "Transcription runs locally. Only the latest transcript is retained for recovery."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
}
