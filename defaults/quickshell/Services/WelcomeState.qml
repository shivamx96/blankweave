import QtQuick
QtObject {
    id: root
    required property var preferences
    property bool eligible: false
    property bool requested: false
    property bool presented: false
    property bool busy: false
    property bool blocked: false
    readonly property bool pending: preferences.ready && (requested || (eligible && !preferences.welcomeShown))
    readonly property bool visible: pending && !blocked && presented
    onPendingChanged: evaluate()
    onBusyChanged: evaluate()
    onBlockedChanged: evaluate()
    onRequestedChanged: evaluate()
    function evaluate() {
        if (pending && !blocked && (!busy || requested)) presented = true
    }
    function dismiss() {
        if (!pending) return
        preferences.welcomeShown = true
        requested = false
        presented = false
    }
    function reopen() { requested = true }
    function activity() { if (presented) dismiss() }
}
