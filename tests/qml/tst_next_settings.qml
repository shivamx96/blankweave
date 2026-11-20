import QtQuick
import QtTest
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog
import "../../defaults/quickshell/Services/SettingsOutcome.js" as Outcomes
import "../../defaults/quickshell/Settings"
TestCase {
    id: test
    name: "NextSettings"
    visible: true
    when: windowShown
    width: 600; height: 800
    property var themePalette: ({
        borderWidth: 1, headingSize: 22, textWeight: 400, headingWeight: 600, motionDuration: 0, motionEasing: Easing.OutCubic,
        spacing: function(name) { return ({xxs:2,xs:4,sm:6,md:8,lg:10,xl:12,section:14,panel:18,content:32,labelGap:5,descriptionGap:9,group:16,page:20,controlInset:24,rowInset:28})[name] },
        designValue: function(group, name, fallback) { return fallback },focusIndicator:"#77aaff",surface:"#112233",surfaceRaised:"#223344",surfaceHover:"#334455",surfacePressed:"#445566",
        text:"#ffffff",textMuted:"#aabbcc",accent:"#77aaff",accentBright:"#77aaff",accentSurface:"#223355",outline:"#445566",
        critical:"#ff7777",warning:"#ffaa33",fontFamily:"sans-serif",textSize:13,smallTextSize:12,widgetRadius:4,reducedMotion:true})
    QtObject {
        id: fakeBackend
        property bool ready: true
        property bool writable: true
        property bool busy: false
        property bool writing: false
        property string error: ""
        property var outcomes: ({})
        function outcome(action, target) { return outcomes[JSON.stringify([action, target || ""])] || null }
        function clearOutcome(action, target) { const next = Object.assign({}, outcomes); delete next[JSON.stringify([action, target || ""])]; outcomes = next }
        function fail(action, target) { const next = Object.assign({}, outcomes); next[JSON.stringify([action, target || ""])] = {message: "Could not apply this change. Try again.", detail: "Safe diagnostic", cancelled: false}; outcomes = next }
        property var request: null
        property string revision: ""
        property var data: ({revision: "original", policy: {manual: false, schedule: false, start: "22:00", end: "08:00", blocked: []}, paused: false, quiet: false, apps: ["Mail"], browser: true, available: true, report: null, details: [], rows: []})
        function apply(value, stamp) { request = value; revision = stamp || data.revision }
        function refresh(clear) { error = "" }
    }
    Component { id: notifications; SettingsNotifications { theme: test.themePalette; backend: fakeBackend; settingId: "dnd" } }
    Component { id: startup; SettingsStartup { theme: test.themePalette; backend: fakeBackend } }
    Component { id: wallpaper; SettingsWallpaper { theme: test.themePalette; backend: fakeBackend } }
    Component { id: webapps; SettingsWebapps { theme: test.themePalette; backend: fakeBackend } }
    Component { id: systemInfo; SettingsSystem { theme: test.themePalette; backend: fakeBackend; settingId: "diagnostics" } }
    function find(parent, text) {
        if (parent.text === text && typeof parent.clicked === "function") return parent
        for (const child of parent.children || []) { const result = find(child, text); if (result) return result }
        return null
    }
    function test_notification_page_keeps_row_ids_and_font_link() {
        const page = Catalog.pages.find(p => p.id === "alerts")
        compare(page.groups[0].rows.map(row => row.id).join(","), "dnd,notifications")
        const input = Catalog.pages.find(p => p.id === "input")
        const link = input.groups[1].rows.find(row => row.id === "large-text")
        compare(link.kind, "link"); compare(link.target, "fonts")
    }
    function init() { fakeBackend.outcomes = ({}); fakeBackend.request = null; fakeBackend.ready = true; fakeBackend.writable = true; fakeBackend.data = {revision: "original", policy: {manual: false, schedule: false, start: "22:00", end: "08:00", blocked: []}, paused: false, quiet: false, apps: ["Mail"], browser: true, available: true, report: null, details: [], rows: []} }
    function test_manual_and_schedule_buttons() {
        const item = createTemporaryObject(notifications, test)
        find(item, "Do not disturb").clicked()
        compare(fakeBackend.request, {action: "manual", value: true})
        find(item, "Quiet hours").clicked()
        compare(fakeBackend.request, {action: "schedule", enabled: true, start: "22:00", end: "08:00"})
    }
    function test_notification_toggle_follows_actual_pause_state() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {paused: true})
        const item = createTemporaryObject(notifications, test)
        find(item, "Do not disturb").clicked()
        compare(fakeBackend.request, {action: "manual", value: false})
    }
    function test_app_notification_control_uses_app_identity() {
        const item = createTemporaryObject(notifications, test, {settingId: "notifications"})
        find(item, "Mute popups").clicked()
        compare(fakeBackend.request, {action: "app", app: "Mail", blocked: true})
    }
    function test_startup_keeps_entry_identity() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {rows: [{id: "one.desktop", name: "One", source: "System", enabled: true, writable: true, reset: false, reason: ""}]})
        const item = createTemporaryObject(startup, test)
        find(item, "Start at sign-in").clicked()
        compare(fakeBackend.request, {action: "enable", id: "one.desktop", enabled: false})
    }
    function test_wallpaper_disconnect_cannot_retarget_edit() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {rows: [{id: "screen1", name: "DP-1", label: "One", path: "/one.png", fit: "crop", custom: true}]})
        const item = createTemporaryObject(wallpaper, test)
        item.beginEdit()
        fakeBackend.data = Object.assign({}, fakeBackend.data, {revision: "changed", rows: [{id: "screen2", name: "DP-2", label: "Two", path: "/two.png", fit: "crop", custom: true}]})
        find(item, "Apply").clicked()
        compare(fakeBackend.request.id, "screen1"); compare(fakeBackend.revision, "original")
    }
    function test_webapp_removal_confirmation_freezes_revision() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {rows: [{id: "one", name: "One", url: "https://example.com", origin: "user", removable: true}]})
        const item = createTemporaryObject(webapps, test)
        const remove = find(item, "Remove")
        remove.clicked(); compare(fakeBackend.request, null)
        verify(remove.armed)
        fakeBackend.data = Object.assign({}, fakeBackend.data, {revision: "changed"})
        verify(!remove.armed)
        remove.clicked(); compare(fakeBackend.request, null)
        remove.clicked()
        compare(fakeBackend.request, {action: "remove", id: "one"}); compare(fakeBackend.revision, "changed")
    }
    function test_diagnostics_are_explicit() {
        const item = createTemporaryObject(systemInfo, test)
        compare(fakeBackend.request, null)
        find(item, "Run health checks").clicked(); compare(fakeBackend.request, {action: "diagnose"})
    }
    function test_outcome_placement_data() {
        return [
            {tag: "startup", factory: startup, action: "enable", target: "one", button: "Start at sign-in"},
            {tag: "webapps", factory: webapps, action: "remove", target: "one", button: "Remove"},
            {tag: "create", factory: webapps, action: "create", target: "", button: "Add web app"},
            {tag: "wallpaper", factory: wallpaper, action: "set", target: "one", button: "Apply"},
            {tag: "diagnostics", factory: systemInfo, action: "diagnose", target: "", button: "Run health checks"},
            {tag: "notifications", factory: notifications, action: "manual", target: "", button: "Do not disturb"}
        ]
    }
    function test_outcome_placement(row) {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {rows: [{id:"one",name:"One",source:"User",enabled:true,writable:true,reset:true,reason:"",url:"https://example.com",origin:"user",removable:true,label:"One",path:"/one.png",fit:"crop",custom:true}]})
        const item = createTemporaryObject(row.factory, test, {width: 500})
        fakeBackend.fail(row.action, row.target)
        const result = findChild(item, "actionResult:" + row.action + ":" + row.target)
        verify(result !== null); compare(result.message, "Could not apply this change. Try again.")
        item.height = item.implicitHeight
        wait(30)
        const control = find(item, row.button)
        verify(control !== null)
        verify(result.mapToItem(item,0,0).y >= control.mapToItem(item,0,control.height).y)
        const details = findChild(result, "settingsResultDetails")
        verify(!details.visible); result.expanded = true; compare(details.text, "Safe diagnostic")
        fakeBackend.clearOutcome(row.action, row.target); compare(result.message, "")
    }
    function test_row_result_follows_identity_on_refresh() {
        const one = {id:"one",name:"One",url:"https://example.com",origin:"user",removable:true}
        const two = Object.assign({}, one, {id:"two",name:"Two"})
        fakeBackend.data = Object.assign({}, fakeBackend.data, {rows:[one,two]})
        const item = createTemporaryObject(webapps,test,{width:500})
        fakeBackend.fail("remove","one")
        fakeBackend.data = Object.assign({}, fakeBackend.data, {revision:"new",rows:[two,one]})
        compare(findChild(item,"actionResult:remove:one").message,"Could not apply this change. Try again.")
        compare(findChild(item,"actionResult:remove:two").message,"")
    }
    function test_input_edit_clears_only_related_result() {
        const item = createTemporaryObject(webapps,test)
        fakeBackend.fail("create",""); fakeBackend.fail("remove","one")
        function field(parent) {
            if (parent.Accessible && parent.Accessible.name === "Web app name") return parent
            for (const child of parent.children || []) { const result = field(child); if (result) return result }
            return null
        }
        field(item).textEdited()
        compare(fakeBackend.outcome("create", ""),null)
        verify(fakeBackend.outcome("remove", "one") !== null)
    }

    function test_outcome_capture_does_not_retain_operation_secrets() {
        const request = Outcomes.capture("operations-settings.py", {action:"connect",id:"one",password:"private",values:{password:"private"}})
        verify(JSON.stringify(request).indexOf("private") < 0)
        compare(Outcomes.observed("operations-settings.py",request,{revision:"b"},{revision:"a"}),null)
    }
    function test_notification_app_result_survives_reorder() {
        fakeBackend.data = Object.assign({},fakeBackend.data,{apps:["Mail","Chat"]})
        const item = createTemporaryObject(notifications,test,{settingId:"notifications"})
        fakeBackend.fail("app","Mail")
        fakeBackend.data = Object.assign({},fakeBackend.data,{apps:["Chat","Mail"]})
        compare(findChild(item,"actionResult:app:Mail").message,"Could not apply this change. Try again.")
        compare(findChild(item,"actionResult:app:Chat").message,"")
    }
    function test_startup_result_survives_reorder() {
        const one = {id:"one",name:"One",source:"User",enabled:true,writable:true,reset:false,reason:""}
        const two = Object.assign({},one,{id:"two",name:"Two"})
        fakeBackend.data = Object.assign({},fakeBackend.data,{rows:[one,two]})
        const item = createTemporaryObject(startup,test)
        fakeBackend.fail("enable","one")
        fakeBackend.data = Object.assign({},fakeBackend.data,{rows:[two,one]})
        compare(findChild(item,"actionResult:enable:one").message,"Could not apply this change. Try again.")
        compare(findChild(item,"actionResult:enable:two").message,"")
    }

}
