import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
TestCase {
    id: test
    name: "NextSettings"
    width: 600; height: 800
    property var themePalette: ({surface:"#112233",surfaceRaised:"#223344",surfaceHover:"#334455",surfacePressed:"#445566",
        text:"#ffffff",textMuted:"#aabbcc",accent:"#77aaff",accentBright:"#77aaff",accentSurface:"#223355",outline:"#445566",
        warning:"#ffaa33",fontFamily:"sans-serif",textSize:13,smallTextSize:12,widgetRadius:4,reducedMotion:true})
    QtObject {
        id: fakeBackend
        property bool ready: true
        property bool writable: true
        property bool busy: false
        property bool writing: false
        property string error: ""
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
    function init() { fakeBackend.request = null; fakeBackend.ready = true; fakeBackend.writable = true; fakeBackend.data = {revision: "original", policy: {manual: false, schedule: false, start: "22:00", end: "08:00", blocked: []}, paused: false, quiet: false, apps: ["Mail"], browser: true, available: true, report: null, details: [], rows: []} }
    function test_manual_and_schedule_buttons() {
        const item = createTemporaryObject(notifications, test)
        find(item, "Turn on manual DND").clicked()
        compare(fakeBackend.request, {action: "manual", value: true})
        find(item, "Save quiet hours").clicked()
        compare(fakeBackend.request, {action: "schedule", enabled: true, start: "22:00", end: "08:00"})
    }
    function test_app_notification_control_uses_app_identity() {
        const item = createTemporaryObject(notifications, test, {settingId: "notifications"})
        find(item, "Mute popups").clicked()
        compare(fakeBackend.request, {action: "app", app: "Mail", blocked: true})
    }
    function test_startup_keeps_entry_identity() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {rows: [{id: "one.desktop", name: "One", source: "System", enabled: true, writable: true, reset: false, reason: ""}]})
        const item = createTemporaryObject(startup, test)
        find(item, "Disable").clicked()
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
        find(item, "Remove…").clicked(); compare(fakeBackend.request, null)
        fakeBackend.data = Object.assign({}, fakeBackend.data, {revision: "changed", rows: []})
        find(item, "Remove web app").clicked()
        compare(fakeBackend.request, {action: "remove", id: "one"}); compare(fakeBackend.revision, "original")
    }
    function test_diagnostics_are_explicit() {
        const item = createTemporaryObject(systemInfo, test)
        compare(fakeBackend.request, null)
        find(item, "Run health checks").clicked(); compare(fakeBackend.request, {action: "diagnose"})
    }
}
