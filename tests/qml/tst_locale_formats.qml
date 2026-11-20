import QtQuick
import QtTest
import "../../defaults/quickshell/Components/LocaleFormats.js" as Formats
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog
TestCase {
    name: "LocaleFormats"
    function test_time() {
        const date = new Date(2026, 0, 2, 13, 5, 9)
        compare(Formats.time(date, "12h", Qt.locale("en_US"), false), "1:05 PM")
        compare(Formats.time(date, "24h", Qt.locale("en_US"), true), "13:05:09")
        compare(Formats.time(date, "auto", Qt.locale("en_US"), false), "1:05 PM")
        compare(Formats.time(date, "auto", Qt.locale("de_DE"), false), "13:05")
        compare(Formats.time(new Date(2026, 0, 2, 0, 0), "12h", Qt.locale("en_US"), false), "12:00 AM")
        compare(Formats.time("bad", "24h", Qt.locale("de_DE")), "—")
    }
    function test_temperature() {
        compare(Formats.temperature(0, "fahrenheit", Qt.locale("de_DE")), 32)
        compare(Formats.temperature(21.4, "fahrenheit", Qt.locale("de_DE")), 71)
        compare(Formats.temperature(-40, "fahrenheit", Qt.locale("de_DE")), -40)
        compare(Formats.temperature(21.6, "celsius", Qt.locale("en_US")), 22)
        compare(Formats.temperature(0, "auto", Qt.locale("en_US")), 32)
        compare(Formats.temperature(0, "auto", Qt.locale("de_DE")), 0)
        compare(Formats.suffix("auto", Qt.locale("en_GB")), "°C")
    }
    function test_normalization() {
        compare(Formats.normalizeTime("bogus"), "auto")
        compare(Formats.normalizeTemperature("kelvin"), "auto")
        compare(Formats.normalizeTime("24h"), "24h")
        compare(Formats.normalizeTemperature("fahrenheit"), "fahrenheit")
    }
    function test_catalog() {
        const rows = Catalog.pages[0].groups.reduce((all, group) => all.concat(group.rows), [])
        const time = rows.find(row => row.id === "time-format")
        const temperature = rows.find(row => row.id === "temperature-unit")
        verify(time.live); verify(temperature.live)
        for (const alias of ["clock", "12 hour", "24 hour", "am pm"]) verify(time.aliases.includes(alias))
        for (const alias of ["celsius", "fahrenheit", "units"]) verify(temperature.aliases.includes(alias))
    }
}
