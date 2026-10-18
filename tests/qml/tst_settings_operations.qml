import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog
TestCase {
    id: test
    name: "SettingsOperations"
    width: 600; height: 800
    when: windowShown
    property var themePalette: ({surface:"#112233",panelSurface:"#112233",surfaceRaised:"#223344",surfaceHover:"#334455",surfacePressed:"#445566",
        text:"#ffffff",textMuted:"#aabbcc",accent:"#77aaff",accentBright:"#77aaff",accentSurface:"#223355",outline:"#445566",
        warning:"#ffaa33",fontFamily:"sans-serif",textSize:13,smallTextSize:12,widgetRadius:4,reducedMotion:true})
    QtObject {
        id: fakeBackend
        property bool ready: true
        property bool writable: true
        property bool busy: false
        property bool writing: false
        property string error: ""
        property var data: ({})
        property var request: null
        property string stamp: ""
        property string cancelled: ""
        function apply(value, revision) { request = value; stamp = revision }
        function refresh(clear) { error = "" }
        function cancelJob(id) { cancelled = id }
    }
    Component { id: view; SettingsOperations { theme: test.themePalette; settingId: "drives"; backend: fakeBackend } }
    function button(parent, text) {
        if (parent.text === text && typeof parent.clicked === "function") return parent
        for (const child of parent.children || []) { const found = button(child, text); if (found) return found }
        return null
    }
    function init() {
        fakeBackend.ready = true; fakeBackend.writable = true; fakeBackend.busy = false; fakeBackend.request = null; fakeBackend.cancelled = ""
        fakeBackend.data = {revision:"original", details:["Device present"], message:"", job:null, actions:[{
            key:"eject",label:"Eject",confirm:"Eject this device?",cancellable:false,
            fields:[{key:"device",label:"Device",value:"old-device",options:[{value:"old-device",label:"USB drive"}],secret:false}]
        }]}
    }
    function test_catalog_has_real_provider_kinds_for_all_remaining_rows() {
        let count = 0
        for (const page of Catalog.pages) for (const group of page.groups) for (const row of group.rows) {
            verify(row.kind !== "action")
            if (row.kind === "operations") { verify(row.live); count++ }
        }
        compare(count, 17)
    }
    function test_view_does_not_write_until_confirmed() {
        const item = createTemporaryObject(view, test)
        compare(fakeBackend.request, null)
        item.begin(fakeBackend.data.actions[0]); compare(fakeBackend.request, null)
        button(item, "Eject").clicked()
        compare(fakeBackend.request, {action:"eject",device:"old-device",confirmed:true})
        compare(fakeBackend.stamp, "original")
    }
    function test_styled_choices_display_labels_and_submit_values() {
        const item = createTemporaryObject(view, test, {width: 550})
        const operation = findChild(item, "operationChoice")
        compare(operation.theme, test.themePalette)
        operation.popup.open()
        tryCompare(operation.popup, "opened", true)
        tryVerify(() => operation.popup.contentItem.itemAtIndex(0) !== null)
        compare(operation.popup.contentItem.itemAtIndex(0).text, "Eject")
        compare(operation.popup.background.color, test.themePalette.panelSurface)
        operation.popup.close()
        item.begin(fakeBackend.data.actions[0])
        const choice = findChild(item, "operationFieldChoice")
        verify(choice !== null)
        compare(choice.theme, test.themePalette)
        choice.popup.open()
        tryCompare(choice.popup, "opened", true)
        tryVerify(() => choice.popup.contentItem.itemAtIndex(0) !== null)
        compare(choice.popup.contentItem.itemAtIndex(0).text, "USB drive")
        compare(choice.currentValue, "old-device")
        choice.activated(0)
        choice.popup.close()
        item.submit()
        compare(fakeBackend.request.device, "old-device")
    }
    function test_confirmation_freezes_target_and_revision() {
        const item = createTemporaryObject(view, test)
        item.begin(fakeBackend.data.actions[0])
        fakeBackend.data = {revision:"new",details:[],actions:[],job:null}
        item.submit()
        compare(fakeBackend.request.device, "old-device"); compare(fakeBackend.stamp, "original")
    }
    function test_cancel_discards_secret_input() {
        const item = createTemporaryObject(view, test)
        item.begin({key:"unlock",label:"Unlock",confirm:"",fields:[{key:"password",label:"Password",value:"",options:[],secret:true}]})
        item.values.password = "secret"
        button(item, "Cancel").clicked()
        compare(item.values, {}); compare(item.editing, null); compare(fakeBackend.request, null)
    }
    function test_busy_provider_disables_operation() {
        fakeBackend.writable = false
        const item = createTemporaryObject(view, test)
        verify(!button(item, "Configure…").enabled)
    }
    function test_job_cancellation_uses_captured_identity() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {job:{id:"job-1",label:"Scan",phase:"running",message:"",cancellable:true}})
        const item = createTemporaryObject(view, test)
        button(item, "Cancel operation").clicked()
        compare(fakeBackend.cancelled, "job-1")
    }
}
