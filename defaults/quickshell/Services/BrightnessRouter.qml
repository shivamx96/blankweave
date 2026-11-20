pragma ComponentBehavior: Bound
import QtQuick

// Prefer the bar's live instance; absent/hidden bars use a one-shot reader.
Item {
    id: root
    required property var osd
    property var screens: []
    property string focusedScreenName: ""
    property string helper: ""
    property var registered: []
    property var cached: []
    function registerDisplay(display) { registered = registered.concat([display]) }
    function unregisterDisplay(display) { registered = registered.filter(d => d !== display) }
    function target() {
        return screens.find(s => s.name === focusedScreenName) || screens[0] || null
    }
    function adjust(action) {
        if (!["up", "down"].includes(action)) return
        const screen = target()
        if (!screen) return
        let display = registered.find(d => d.connector === screen.name && d.active)
            || cached.find(d => d.connector === screen.name)
        if (!display) {
            const props = {screen: screen, polling: false}
            if (helper) props.helper = helper
            display = factory.createObject(root, props)
            cached = cached.concat([display])
        }
        display.step(action === "up" ? 5 : -5)
    }
    onScreensChanged: {
        for (const d of cached) if (!screens.some(s => s.name === d.connector)) d.destroy()
        cached = cached.filter(d => screens.some(s => s.name === d.connector))
    }
    Component {
        id: factory
        DisplayBrightness {
            onStepRequested: value => root.osd.show("brightness", "Brightness · " + value + "%", "󰃟", value / 100)
        }
    }
}
