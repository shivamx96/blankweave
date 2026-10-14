.pragma library
var groups = {
    left: ["overview", "workspaces", "window"],
    center: ["weather", "clock"],
    right: ["indicators", "brightness", "audio", "bluetooth", "network", "notifications", "battery", "memory", "cpu", "gpu", "power"]
}
var labels = {overview: "System menu", workspaces: "Workspaces", window: "Active window", weather: "Weather", clock: "Clock", indicators: "Application indicators", brightness: "Brightness", audio: "Sound", bluetooth: "Bluetooth", network: "Network", notifications: "Notifications", battery: "Battery", memory: "Memory", cpu: "CPU", gpu: "GPU", power: "Power menu"}
function order(group, saved) {
    const allowed = groups[group] || []
    const values = String(saved || "").split(",").filter((id, i, all) => allowed.includes(id) && all.indexOf(id) === i)
    return values.concat(allowed.filter(id => !values.includes(id)))
}
function hidden(saved) { return String(saved || "").split(",").filter(id => labels[id] && !["overview", "power"].includes(id)) }
function move(group, saved, id, delta) {
    const values = order(group, saved), index = values.indexOf(id), target = index + delta
    if (index < 0 || target < 0 || target >= values.length || ![-1, 1].includes(delta)) return values.join(",")
    values.splice(index, 1); values.splice(target, 0, id)
    return values.join(",")
}
