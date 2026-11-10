import QtQuick
import QtTest
import "../../defaults/quickshell/Components"

TestCase {
    name: "ThemeSurface"
    when: windowShown
    width: 200; height: 100; visible: true
    QtObject {
        id: palette
        property bool gradientEnabled: false
        property bool gradientHorizontal: false
        property color gradientStart: "#804080c0"
        property color gradientEnd: "#80c08040"
    }
    ThemeSurface {
        id: surface
        surfaceTheme: palette
        anchors.fill: parent
        color: "#121212"
        radius: 8
        Rectangle { id: control; width: 20; height: 20; color: "white" }
    }
    function test_material_is_optional_and_preserves_content() {
        const wash = surface.children[0]
        compare(wash.border.width, 0)
        verify(!wash.visible)
        palette.gradientEnabled = true
        verify(wash.visible)
        compare(wash.radius, surface.radius)
        compare(wash.gradient.orientation, Gradient.Vertical)
        palette.gradientHorizontal = true
        compare(wash.gradient.orientation, Gradient.Horizontal)
        surface.decorative = false
        verify(!wash.visible)
        verify(control.visible)
        compare(surface.color, "#121212")
    }
}
