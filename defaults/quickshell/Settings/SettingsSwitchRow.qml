import QtQuick
import QtQuick.Layouts

// checked is backend readback; requested is presentation only, never written to it.
ColumnLayout {
    id: root
    required property var theme
    property string text: ""
    property string description: ""
    property bool checked: false
    property bool busy: false
    property string error: ""
    property string detail: ""
    property string identity: ""
    property bool touched: false
    property bool pending: false
    property bool requested: false
    property bool sawBusy: false
    signal clicked()
    signal toggled(bool value)
    function activate() {
        if (!enabled || pending) return
        touched = true
        requested = !checked
        pending = true
        sawBusy = busy
        clicked()
        toggled(requested)
        settleNow.restart()
    }
    onBusyChanged: {
        if (pending && busy) sawBusy = true
        if (pending && !busy && sawBusy) settleAfterBusy.restart()
    }
    onCheckedChanged: if (pending && checked === requested && !busy) pending = false
    onErrorChanged: if (error && !busy) pending = false
    onIdentityChanged: { pending = false; touched = false }
    // Timers, not Qt.callLater: a deferred closure outlives a row that a list
    // refresh destroys and then writes to a context that no longer exists.
    Timer {
        id: settleNow
        interval: 0
        onTriggered: if (!root.busy && (root.checked === root.requested || root.error)) root.pending = false
    }
    Timer {
        id: settleAfterBusy
        interval: 1
        onTriggered: if (!root.busy) root.pending = false
    }
    RowLayout {
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: root.text; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.textSize }
            Text { Layout.fillWidth: true; visible: text !== ""; text: root.description; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize }
        }
        SettingsSwitch {
            id: control
            theme: root.theme
            objectName: "switchControl"
            checked: root.pending ? root.requested : root.checked
            pending: root.pending
            enabled: root.enabled && !root.pending
            Accessible.name: root.text
            Accessible.description: root.description
            onToggled: { root.activate(); checked = Qt.binding(() => root.pending ? root.requested : root.checked) }
        }
    }
    Text { Layout.fillWidth: true; visible: root.pending; text: root.requested ? "Turning on…" : "Turning off…"; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize }
    SettingsResult { theme: root.theme; cancelled: root.error === "Cancelled"; message: root.error; detail: root.detail; visible: root.touched && !root.pending && message !== "" }
}
