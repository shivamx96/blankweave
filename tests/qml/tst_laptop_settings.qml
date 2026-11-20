import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog
import "../../defaults/quickshell/Settings/DateTime.js" as Clock
TestCase {
    id: test
    name: "LaptopSettings"
    width: 500; height: 600
    when: windowShown
    visible: true
    property var palette: ({spacing: name => 8, fontFamily:"sans-serif",textWeight:400,smallTextSize:12,textSize:14,text:"white",textMuted:"gray",critical:"red",accentBright:"cyan",accentSurface:"#123456",surfacePressed:"#333333",surfaceHover:"#444444",surfaceRaised:"#222222",panelSurface:"#111111",outline:"gray",borderWidth:1,widgetRadius:4})
    Component { id: combo; SettingsComboBox { theme: test.palette; width: 350 } }
    Component { id: calendar; SettingsDateTimeFields { theme: test.palette } }
    function test_date_fields_respect_preference_and_validate() {
        const item = createTemporaryObject(calendar, test, {timeFormat:"12h",parts:[2028,2,29,11,45,0],period:"PM"})
        compare(item.composed,"2028-02-29 23:45:00")
        item.parts = [2027,2,29,11,45,0]
        compare(item.composed,"")
        item.timeFormat = "24h"; item.parts = [2028,1,1,23,59,59]
        compare(item.composed,"2028-01-01 23:59:59")
    }
    function test_short_menu_unchanged() {
        const item = createTemporaryObject(combo, test, {model:["One","Two"]})
        verify(!item.searchable)
        item.popup.open(); wait(30)
        verify(!findChild(item.popup.contentItem, "comboFilter").visible)
        compare(item.popup.contentItem.count, 2)
        item.popup.close()
    }
    function test_filter_labels_values_and_keyboard() {
        let options = []
        for (let i=0; i<15; i++) options.push({label:"City " + i,value:"zone-"+i})
        const item = createTemporaryObject(combo, test, {model:options,textRole:"label",valueRole:"value"})
        verify(item.searchable)
        item.popup.open(); wait(30)
        const input = findChild(item.popup.contentItem, "comboFilter")
        input.text = ""; input.forceActiveFocus(); keyClick(Qt.Key_Z); compare(input.text, "z")
        input.text = "ZONE-1"; input.forceActiveFocus(); wait(20)
        verify(input.activeFocus)
        compare(item.filteredIndices.length, 6)
        keyClick(Qt.Key_Down); compare(item.filterIndex, 1)
        keyClick(Qt.Key_Up); compare(item.filterIndex, 0)
        keyClick(Qt.Key_Escape); compare(input.text, ""); verify(item.popup.visible)
        input.text = "city 14"; wait(20); compare(item.filteredIndices.length,1); compare(item.filteredIndices[0],14); verify(input.activeFocus)
        keyClick(Qt.Key_Return); compare(item.currentValue, "zone-14"); verify(!item.popup.visible)
        item.popup.open(); wait(20); keyClick(Qt.Key_Escape); verify(!item.popup.visible)
    }
    function test_calendar_ranges_and_twelve_hour_composition() {
        compare(Clock.compose(2028,2,29,12,30,0,"12h","AM"), "2028-02-29 00:30:00")
        compare(Clock.compose(2028,2,29,12,30,0,"12h","PM"), "2028-02-29 12:30:00")
        compare(Clock.compose(2027,2,29,2,0,0,"24h","AM"), "")
        compare(Clock.compose(2028,1,1,24,0,0,"24h","AM"), "")
        compare(Clock.compose(2028,1,1,1,60,0,"24h","AM"), "")
    }
    function test_capability_pages_search_failopen_and_stable_ids() {
        const hidden = Catalog.visiblePages([])
        verify(!hidden.find(p => p.id === "network").groups[0].rows.some(r => r.id === "wifi"))
        verify(!Catalog.searchSettings("bluetooth", []).some(r => r.id === "bluetooth"))
        verify(Catalog.searchSettings("bluetooth", null).some(r => r.id === "bluetooth"))
        const rows = Catalog.pages.reduce((all,p) => all.concat(p.groups.reduce((all,g) => all.concat(g.rows),[])),[])
        compare(rows.find(r => r.id === "large-text").target, "fonts")
        compare(rows.filter(r => r.title === "Text size" && r.kind === "interface-size").length, 1)
        compare(Catalog.searchSettings("notification preferences")[0].pageId, "alerts")
    }
}
