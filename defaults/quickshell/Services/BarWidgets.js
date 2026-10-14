.pragma library
var groups = {
    left: ["overview", "workspaces", "window"],
    center: ["weather", "clock"],
    right: ["indicators", "brightness", "audio", "bluetooth", "network", "notifications", "battery", "memory", "cpu", "gpu", "power"]
}
var labels = {overview: "System menu", workspaces: "Workspaces", window: "Active window", weather: "Weather", clock: "Clock", indicators: "Application indicators", brightness: "Brightness", audio: "Sound", bluetooth: "Bluetooth", network: "Network", notifications: "Notifications", battery: "Battery", memory: "Memory", cpu: "CPU", gpu: "GPU", power: "Power menu"}
function cluster(id) {
    if (id === "indicators") return 0
    if (["brightness", "audio", "bluetooth", "network", "notifications", "battery"].includes(id)) return 1
    return 2
}
function canMove(group, values, index, delta) {
    const target = index + delta
    return index >= 0 && target >= 0 && target < values.length && [-1, 1].includes(delta)
        && (group !== "right" || cluster(values[index]) === cluster(values[target]))
}
function dividerBefore(group, visibleIds, id) {
    const index = visibleIds.indexOf(id)
    return group === "right" && index > 0 && cluster(visibleIds[index - 1]) !== cluster(id)
}
function order(group, saved) {
    const allowed = groups[group] || []
    const values = String(saved || "").split(",").filter((id, i, all) => allowed.includes(id) && all.indexOf(id) === i)
    const complete = values.concat(allowed.filter(id => !values.includes(id)))
    if (group !== "right") return complete
    return complete.filter(id => cluster(id) === 0).concat(complete.filter(id => cluster(id) === 1), complete.filter(id => cluster(id) === 2))
}
function hidden(saved) { return String(saved || "").split(",").filter(id => labels[id] && !["overview", "power"].includes(id)) }
function move(group, saved, id, delta) {
    const values = order(group, saved), index = values.indexOf(id), target = index + delta
    if (!canMove(group, values, index, delta)) return values.join(",")
    values.splice(index, 1); values.splice(target, 0, id)
    return values.join(",")
}
