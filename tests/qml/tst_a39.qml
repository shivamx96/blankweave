import QtQuick
import QtQuick.Layouts
import QtTest
import "../../defaults/quickshell/Components"
import "../../defaults/quickshell/Components/PopupGeometry.js" as Geometry
import "../../defaults/quickshell/Components/PanelNavigation.js" as Navigation
import "../../defaults/quickshell/Services/LauncherUsage.js" as Usage
import "../../defaults/quickshell/Assets/marks.js" as Marks

TestCase {
    name: "A39"
    when: windowShown
    width: 400; height: 400
    property var theme: ({spacing: function() { return 8 }, textMuted: "white"})
    PanelViewport {
        id: viewport
        theme: parent.theme
        width: 300; height: Math.min(Geometry.maximum(264, 40), naturalHeight)
        Column {
            Repeater { model: 20; Rectangle { width: 100; height: 30 } }
            Item { id: last; width: 100; height: 30 }
        }
    }
    PanelViewport {
        id: shortPanel
        theme: parent.theme
        width: 300; height: Math.min(Geometry.maximum(264, 40), naturalHeight)
        Rectangle { implicitWidth: 100; implicitHeight: 40 }
    }
    function test_viewport() {
        compare(Geometry.maximum(264, 40), 200)
        compare(viewport.height, 200)
        verify(viewport.overflowing)
        Navigation.reveal(last)
        verify(viewport.contentY > 0)
        compare(shortPanel.height, 40)
        compare(shortPanel.naturalHeight, 40)
        verify(!shortPanel.overflowing)
    }
    function test_usage() {
        const now = 1800000000000, month = 2592000000
        compare(Usage.score({count: 7, last: now}, now), 3)
        compare(Usage.score({count: 7, last: now - month}, now), 1.5)
        verify(Usage.score({count: 100, last: now - 6*month}, now) < Usage.score({count: 1, last: now}, now))
        compare(Usage.score(null, now), 0)
        compare(JSON.stringify(Usage.clean({gone:{count:2,last:now},bad:{count:-1,last:now},ok:{count:1,last:now}}, ["ok","bad"])), JSON.stringify({ok:{count:1,last:now}}))
        const many = {}; const ids = []
        for (let i=0;i<600;i++) { ids.push(String(i)); many[i]={count:1,last:now+i} }
        compare(Object.keys(Usage.clean(many,ids)).length, 512)
        compare(Usage.neutral({categories:["TerminalEmulator"]}), 0)
        compare(Usage.neutral({categories:["WebBrowser"]}), 1)
        compare(Usage.neutral({categories:["FileManager"]}), 2)
        compare(Usage.neutral({categories:["Settings"]}), 3)
        compare(Usage.neutral({categories:[]}), 4)
    }
    function test_marks() {
        const names = ["audio-muted","bluetooth","bluetooth-off","bluetooth-connected","network-disconnected","ethernet","display","notifications","notifications-paused","battery-charging"]
        for (const pair of [["audio",3],["brightness",3],["wifi",5],["battery",6]])
            for(let i=0;i<pair[1];i++) names.push(pair[0]+"-"+i)
        for (const name of names) {
            verify(Marks.has(name), name)
            const svg = Marks.svg(name, "white", "blue")
            verify(svg.includes('viewBox="0 0 24 24"'), name)
            verify(!svg.includes("{fg}") && !svg.includes("{accent}"), name)
        }
    }
}
