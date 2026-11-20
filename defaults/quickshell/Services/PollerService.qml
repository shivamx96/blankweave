import QtQuick

// One registry per shell. Views subscribe; only this object owns processes.
Item {
    id: root
    property var entries: ({})
    visible: false
    Component { id: collector; ScriptPoller { } }

    function acquire(key, view) {
        const created = !entries[key]
        if (created) entries[key] = { poller: collector.createObject(root), views: [] }
        const entry = entries[key]
        if (entry.views.indexOf(view) < 0) entry.views.push(view)
        configure(key)
        if (created) Qt.callLater(entry.poller.refresh)
        return entry.poller
    }
    function configure(key) {
        const entry = entries[key]
        if (!entry || !entry.views.length) return
        // Count all requesting views, including those on a second monitor.
        let selected = entry.views[0]
        for (const view of entry.views) {
            if (view.interval > 0 && (selected.interval <= 0 || view.interval < selected.interval)) selected = view
        }
        entry.poller.interval = selected.interval
        entry.poller.timeout = selected.timeout
        entry.poller.command = selected.command
    }
    function release(key, view) {
        const entry = entries[key]
        if (!entry) return
        entry.views = entry.views.filter(v => v !== view)
        // Keep the cached result, but stop polling when no widget requests it.
        if (!entry.views.length) entry.poller.interval = 0
        else configure(key)
    }
}
