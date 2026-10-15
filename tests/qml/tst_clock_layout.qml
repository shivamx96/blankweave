import QtQuick
import QtTest
import "../../defaults/quickshell/Components"
TestCase {
    id: test
    name: "ClockLayout"
    width: 1000; height: 60
    ClockCenteredLayout {
        id: layout
        anchors.horizontalCenter: parent.horizontalCenter
        clockContent: Rectangle { id: clock; width: 120; height: 30 }
        weatherContent: Rectangle { id: weather; width: 60; height: 30 }
    }
    function init() { layout.clockVisible = true; layout.weatherFirst = true; clock.width = 120; weather.width = 60; wait(0) }
    function test_weather_does_not_shift_clock() {
        const slot = findChild(layout, "centeredClockSlot")
        compare(layout.x + slot.x + clock.width / 2, test.width / 2)
        weather.width = 110; wait(0)
        compare(layout.x + slot.x + clock.width / 2, test.width / 2)
        layout.weatherFirst = false; wait(0)
        compare(layout.x + slot.x + clock.width / 2, test.width / 2)
        const neighbor = findChild(layout, "adjacentWeatherSlot")
        compare(neighbor.x, slot.x + clock.width)
        weather.width = 0; wait(0)
        compare(layout.x + slot.x + clock.width / 2, test.width / 2)
    }
    function test_weather_centers_when_clock_hidden() {
        layout.clockVisible = false; clock.width = 0; wait(0)
        const slot = findChild(layout, "adjacentWeatherSlot")
        compare(layout.x + slot.x + weather.width / 2, test.width / 2)
    }
}
