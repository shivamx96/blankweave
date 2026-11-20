import QtQuick

// A subscription, never a process. The key describes the data, not the screen.
Item {
    id: root
    required property var service
    required property string key
    property string command: ""
    property int interval: 5000
    property int timeout: Math.max(1000, Math.min(30000, interval > 0 ? interval * 0.8 : 10000))
    property var source: null
    property string registeredKey: ""
    property bool initialized: false
    readonly property string output: source ? source.output : ""
    readonly property bool ready: source ? source.ready : false
    readonly property bool running: source ? source.running : false
    readonly property bool stale: source ? source.stale : true
    readonly property string error: source ? source.error : ""
    readonly property double lastUpdated: source ? source.lastUpdated : 0
    readonly property string staleText: source ? source.staleText : "Last updated: never"
    signal updated(string payload)
    visible: false
    function configure() { if (service && source) service.configure(registeredKey) }
    function refresh() {
        configure()
        if (source) {
            // An explicit refresh may carry an uncached request (Git --max-age 0)
            // from either screen, even when another view owns the fastest timer.
            source.command = command
            source.refresh()
        }
    }
    function subscribe() {
        if (!initialized) return
        if (source) service.release(registeredKey, root)
        registeredKey = key
        source = service.acquire(registeredKey, root)
        if (source.ready) Qt.callLater(() => root.updated(source.output))
    }
    onKeyChanged: subscribe()
    onCommandChanged: configure()
    onIntervalChanged: configure()
    onTimeoutChanged: configure()
    Connections {
        target: root.source
        function onUpdated(payload) { root.updated(payload) }
    }
    Component.onCompleted: { initialized = true; subscribe() }
    Component.onDestruction: { if (service && source) service.release(registeredKey, root) }
}
