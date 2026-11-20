import QtQuick

LauncherSession {
    id: root
    property var panels: []
    property bool keyboardRequest: false
    property bool synchronizing: false
    function registerPanel(panel) { panels = panels.concat([panel]) }
    function unregisterPanel(panel) { panels = panels.filter(p => p !== panel) }
    function available(panel, target, id) {
        return panel.panelId === id && panel.bar.screen && panel.bar.screen.name === target
            && panel.anchorItem.visible
    }
    function request(id) {
        const target = chooseTarget()
        if (!panels.some(p => available(p, target, id))) return
        keyboardRequest = true
        if (open && mode === id && targetName === target) { dismiss(); return }
        synchronizing = true
        targetName = target
        mode = id
        open = true
        synchronizing = false
        synchronize()
    }
    function claim(panel) {
        synchronizing = true
        keyboardRequest = false
        targetName = panel.bar.screen ? panel.bar.screen.name : ""
        mode = panel.panelId
        open = true
        synchronizing = false
        synchronize()
    }
    function synchronize() {
        if (synchronizing) return
        synchronizing = true
        for (const panel of panels) panel.open = open && available(panel, targetName, mode)
        synchronizing = false
    }
    onOpenChanged: synchronize()
    onModeChanged: synchronize()
    onTargetNameChanged: synchronize()
}
