.pragma library
// Score = log2(1 + count) * 2^(-ageDays / 30), evaluated at shell startup.
// A shared reference time prevents reordering between opens without a launch.
function score(row, now) {
    return row ? Math.log2(1 + row.count) * Math.pow(2, -Math.max(0, now - row.last) / 2592000000) : 0
}
function clean(value, ids) {
    const rows = {}
    for (const id of Object.keys(value || {}).filter(id => ids.includes(id)).sort()) {
        const row = value[id]
        if (row && Number.isFinite(row.count) && row.count > 0 && Number.isFinite(row.last) && row.last > 0)
            rows[id] = {count: Math.min(1000000, Math.floor(row.count)), last: row.last}
    }
    const bounded = {}
    Object.keys(rows).sort((a,b) => rows[b].last - rows[a].last || a.localeCompare(b)).slice(0,512)
        .forEach(id => bounded[id] = rows[id])
    return bounded
}
function neutral(entry) {
    const categories = entry.categories || []
    const order = ["TerminalEmulator", "WebBrowser", "FileManager", "Settings"]
    for (let i = 0; i < order.length; i++) if (categories.includes(order[i])) return i
    return order.length
}
