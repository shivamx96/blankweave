.pragma library

function normalizeTime(value) {
    return ["auto", "12h", "24h"].indexOf(value) >= 0 ? value : "auto"
}
function normalizeTemperature(value) {
    return ["auto", "celsius", "fahrenheit"].indexOf(value) >= 0 ? value : "auto"
}
function timeMode(mode, locale) {
    return normalizeTime(mode) === "auto"
        ? (/ap/i.test(locale.timeFormat(1)) ? "12h" : "24h")
        : mode
}
function temperatureUnit(unit, locale) {
    // Qt: MetricSystem = 0, ImperialUSSystem = 1, ImperialUKSystem = 2.
    // UK weather convention is Celsius despite imperial road measurements.
    return normalizeTemperature(unit) === "auto"
        ? (locale.measurementSystem === 1 ? "fahrenheit" : "celsius")
        : unit
}
function time(value, mode, locale, seconds) {
    const date = value instanceof Date ? value : new Date(value)
    if (isNaN(date.getTime())) return "—"
    const pattern = timeMode(mode, locale) === "12h"
        ? (seconds ? "h:mm:ss AP" : "h:mm AP")
        : (seconds ? "HH:mm:ss" : "HH:mm")
    return Qt.formatTime(date, pattern)
}
function temperature(value, unit, locale) {
    const number = Number(value)
    return Math.round(temperatureUnit(unit, locale) === "fahrenheit" ? number * 9 / 5 + 32 : number)
}
function suffix(unit, locale) {
    return temperatureUnit(unit, locale) === "fahrenheit" ? "°F" : "°C"
}
