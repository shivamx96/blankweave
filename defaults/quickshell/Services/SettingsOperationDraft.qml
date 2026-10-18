import QtQuick

// Session-only state, owned by the provider rather than the page delegate.
QtObject {
    id: root
    required property var backend
    property var editing: null
    property var values: ({})
    property string revision: ""
    property bool pending: false
    property string jobId: ""
    property string error: ""
    property bool secretsCleared: false
    readonly property bool stale: editing !== null && backend.ready && revision !== backend.data.revision
    function begin(operation) {
        if (pending) return
        editing = JSON.parse(JSON.stringify(operation))
        revision = backend.data.revision
        let initial = {}
        for (const field of editing.fields) initial[field.key] = field.value
        values = initial
        error = ""; jobId = ""; secretsCleared = false
    }
    function setValue(key, value) { values = Object.assign({}, values, {[key]: value}) }
    function clearSecrets() {
        if (!editing) return
        let next = Object.assign({}, values)
        let operation = JSON.parse(JSON.stringify(editing))
        for (const field of operation.fields) {
            if (field.secret) {
                if (next[field.key]) secretsCleared = true
                next[field.key] = ""
                field.value = ""
            }
        }
        values = next
        editing = operation
    }
    function discard() {
        if (pending) return
        editing = null; values = ({}); error = ""; jobId = ""; secretsCleared = false
    }
    function submit() {
        if (!editing || pending || !backend.writable || stale) return
        pending = true; error = ""; jobId = ""
        backend.apply(Object.assign({}, values, {action: editing.key, confirmed: true}), revision)
        clearSecrets()
    }
    function review() {
        if (!editing || pending || !backend.ready) return
        const operation = (backend.data.actions || []).find(a => a.key === editing.key)
        if (!operation) { error = "This action is no longer available. Discard this draft and choose another action."; return }
        const saved = values
        begin(operation)
        let restored = Object.assign({}, values)
        for (const field of editing.fields) {
            if (!field.secret && saved[field.key] !== undefined &&
                (!field.options.length || field.options.some(option => option.value === saved[field.key])))
                restored[field.key] = saved[field.key]
        }
        values = restored
    }
    function reconcile() {
        if (!pending || !jobId) return
        const job = backend.data.job
        if (!job || job.id !== jobId) {
            pending = false
            error = "The operation report is no longer available. Check the current state before retrying."
            return
        }
        if (["starting", "running"].includes(job.phase)) return
        pending = false
        if (job.phase === "completed") discard()
        else error = job.message || "The operation did not complete. Review your inputs before retrying."
    }
    property Connections events: Connections {
        target: root.backend
        function onActiveChanged() { if (!root.backend.active) root.clearSecrets() }
        function onDataChanged() { root.reconcile() }
        function onApplyFinished(success, result) {
            if (!root.pending || root.jobId) return
            if (!success) { root.pending = false; root.error = root.backend.error || "Could not start the operation."; return }
            if (!result || !result.jobId) {
                root.pending = false
                root.error = "Could not track the operation. Refresh and check its result before retrying."
                return
            }
            root.jobId = result.jobId
        }
    }
}
