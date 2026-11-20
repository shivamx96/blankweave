import QtQuick
import QtQuick.Window

SettingsButton {
    id: root
    property string actionText: ""
    property string confirmText: actionText
    property string targetIdentity: ""
    property bool confirmationRequired: true
    property bool armed: false
    property int armTimeout: 5000
    signal confirmed()
    function arm() { if (!enabled) return; forceActiveFocus(); armed = true; expiry.restart() }
    function disarm() { armed = false; expiry.stop() }
    text: armed ? confirmText : actionText
    onClicked: {
        if (!confirmationRequired || armed) { disarm(); confirmed() }
        else arm()
    }
    onTargetIdentityChanged: disarm()
    onActiveFocusChanged: if (!activeFocus) disarm()
    onVisibleChanged: if (!visible) disarm()
    onEnabledChanged: if (!enabled) disarm()
    Keys.onEscapePressed: event => { event.accepted = armed; disarm() }
    Connections { target: root.Window.window; function onVisibleChanged() { if (!root.Window.window.visible) root.disarm() }
        function onActiveChanged() { if (!root.Window.window.active) root.disarm() } }
    Timer { id: expiry; interval: root.armTimeout; onTriggered: root.disarm() }
}
