import QtQuick
import "PanelNavigation.js" as Navigation

MouseArea {
    id: root
    required property var theme
    property bool checkable: false
    property bool checked: false
    property int accessibleRole: Accessible.Button
    property string accessibleName: ""
    property string initialName: ""
    property string focusIdentity: initialName
    property bool keyPressed: false
    property string pressedIdentity: ""
    readonly property bool controlDown: pressed || keyPressed
    readonly property var panel: Navigation.panel(root)
    activeFocusOnTab: enabled && visible && acceptedButtons !== Qt.NoButton
    Accessible.role: accessibleRole
    Accessible.name: accessibleName
    Accessible.checkable: checkable
    Accessible.checked: checked
    Accessible.pressed: controlDown
    Accessible.onPressAction: if (enabled) clicked(null)
    onFocusIdentityChanged: { keyPressed = false; if (activeFocus) focus = false }
    onActiveFocusChanged: {
        keyPressed = false
        if (activeFocus && panel && !panel.focusIdentity) panel.focusIdentity = focusIdentity
    }
    Component.onCompleted: {
        initialName = accessibleName
        Qt.callLater(() => {
        if (panel && panel.focusIdentity && panel.focusIdentity === focusIdentity)
            forceActiveFocus(Qt.TabFocusReason)
        })
    }
    onPressed: {
        if (panel) { panel.focusIdentity = focusIdentity; panel.keyboardMode = false }
        forceActiveFocus(Qt.MouseFocusReason)
    }
    Keys.onPressed: event => {
        if (Navigation.route(root, event)) return
        if (panel) panel.keyboardMode = true
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) {
            if (panel && panel.focusIdentity && panel.focusIdentity !== focusIdentity) { event.accepted = true; return }
            if (!event.isAutoRepeat) { keyPressed = true; pressedIdentity = focusIdentity }
            event.accepted = true
        }
    }
    Keys.onReleased: event => {
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) {
            const activate = keyPressed && pressedIdentity === focusIdentity && enabled
            keyPressed = false
            if (activate && !event.isAutoRepeat) clicked(null)
            event.accepted = true
        }
    }
    Rectangle { anchors.fill: parent; color: root.theme.surfacePressed; opacity: root.controlDown ? 0.65 : 0; z: -1 }
    FocusRing { theme: root.theme }
}
