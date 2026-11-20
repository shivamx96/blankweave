.pragma library
function compose(year, month, day, hour, minute, second, mode, period) {
    if ([year, month, day, hour, minute, second].some(v => !/^[0-9]+$/.test(String(v)))) return ""
    const values = [year, month, day, hour, minute, second].map(Number)
    if (values.some(v => !Number.isInteger(v))) return ""
    let [y, m, d, h, min, sec] = values
    if (mode === "12h") {
        if (h < 1 || h > 12) return ""
        h = h % 12 + (period === "PM" ? 12 : 0)
    }
    if (y < 1970 || y > 9999 || m < 1 || m > 12 || d < 1 || h < 0 || h > 23 || min < 0 || min > 59 || sec < 0 || sec > 59) return ""
    const date = new Date(y, m - 1, d)
    if (date.getFullYear() !== y || date.getMonth() !== m - 1 || date.getDate() !== d) return ""
    const pad = v => String(v).padStart(2, "0")
    return y + "-" + pad(m) + "-" + pad(d) + " " + pad(h) + ":" + pad(min) + ":" + pad(sec)
}
