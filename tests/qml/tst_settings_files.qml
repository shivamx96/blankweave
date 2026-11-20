import QtQuick
import QtQuick.Layouts
import QtTest
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog
TestCase {
    id: test
    name: "SettingsFiles"
    when: windowShown
    width: 360; height: 500
    visible: true
    property var palette: ({
        borderWidth: 1, headingSize: 22, textWeight: 400, headingWeight: 600, motionDuration: 0, motionEasing: Easing.OutCubic,
        spacing: function(name) { return ({xxs:2,xs:4,sm:6,md:8,lg:10,xl:12,section:14,panel:18,content:32,labelGap:5,descriptionGap:9,group:16,page:20,controlInset:24,rowInset:28})[name] },
        designValue: function(group, name, fallback) { return fallback },
        canvas: "#0b111c", panelSurface: "#111a2a", surface: "#162033",
        surfaceRaised: "#1c2940", surfaceHover: "#263955", surfacePressed: "#304563",
        text: "#e7edf7", textMuted: "#a1aec4", accentBright: "#67a6ff",
        accentSurface: "#1e3556", outline: "#33476a", outlineStrong: "#4f75ad", divider: "#23314a",
        warning: "#eab875", critical: "#ff7777", accent: "#67a6ff", fontFamily: "sans-serif", iconFontFamily: "sans-serif",
        textSize: 13, smallTextSize: 12, microTextSize: 11, iconSize: 16, widgetRadius: 4, panelRadius: 14
    })

    property string copied: ""
    property string opened: ""
    QtObject {
        id: fakeFiles
        property var files: ({"~/.config/blankweave/idle.json": {path: "/tmp/config/blankweave/idle.json", display: "~/.config/blankweave/idle.json", exists: true}})
        property var overrides: ({"screen-off": [{display: "~/.config/hypr/hypridle.conf"}]})
        function openFolder(file) { test.opened = file }
    }
    ColumnLayout {
        id: holder
        width: 300
    SettingsStorageLine {
        id: line
        Layout.fillWidth: true
        theme: test.palette
        setting: ({id: "screen-off", file: "~/.config/blankweave/idle.json"})
        access: fakeFiles
        onCopyRequested: text => test.copied = text
    }
    }
    function test_storage() {
        verify(line.visible)
        compare(findChild(line, "settingsStorage_screen-off").text, "Stored in ~/.config/blankweave/idle.json")
        var copy = findChild(line, "settingsCopyPath_screen-off")
        mouseClick(copy)
        compare(copied, "/tmp/config/blankweave/idle.json")
        var open = findChild(line, "settingsOpenFolder_screen-off")
        mouseClick(open)
        compare(opened, "~/.config/blankweave/idle.json")
        copy.forceActiveFocus(); verify(copy.activeFocus)
        keyClick(Qt.Key_Return)
        compare(copied, "/tmp/config/blankweave/idle.json")
        compare(line.overrides[0].display, "~/.config/hypr/hypridle.conf")
        fakeFiles.files = ({})
        verify(!open.visible)
        line.setting = ({id: "readout"})
        verify(!line.visible)
        tryCompare(holder, "implicitHeight", 0)
        line.setting = ({id: "audio", store: "PipeWire / WirePlumber state"})
        verify(line.visible)
        compare(findChild(line, "settingsStorage_audio").text, "Stored in PipeWire / WirePlumber state")
    }
    function test_filename_search() {
        verify(Catalog.searchSettings("idle.json").some(row => row.id === "screen-off"))
        verify(Catalog.searchSettings("shortcuts.lua").some(row => row.id === "shortcuts"))
        verify(!Catalog.searchSettings("Stored in").some(row => row.id === "screen-off"))
    }
}
