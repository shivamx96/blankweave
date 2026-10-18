import QtQuick
import QtTest
import "../../defaults/quickshell/Services"
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
        property bool active: true
        signal applyFinished(bool success, var result)
        property SettingsOperationDraft draft: SettingsOperationDraft { backend: fakeBackend }
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
        fakeBackend.draft.pending = false; fakeBackend.draft.discard(); fakeBackend.error = ""; fakeBackend.active = true
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
        compare(fakeBackend.request, null); compare(item.draft.revision, "original")
        verify(item.draft.stale)
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
    function report(id, phase, message) {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {job:{id:id,phase:phase,message:message || "",label:"Eject",cancellable:false}})
    }
    function test_failed_start_keeps_draft_and_retries() {
        const item = createTemporaryObject(view, test)
        item.begin(fakeBackend.data.actions[0])
        item.submit()
        verify(item.draft.pending)
        fakeBackend.error = "Authorization cancelled"
        fakeBackend.applyFinished(false, null)
        verify(!item.draft.pending)
        compare(item.values.device, "old-device")
        compare(findChild(item, "operationFormError").text, "Authorization cancelled")
        button(item, "Retry Eject").clicked()
        verify(item.draft.pending)
        compare(fakeBackend.request.device, "old-device")
    }
    function test_job_failure_and_cancel_keep_inputs_success_clears() {
        const item = createTemporaryObject(view, test)
        item.begin(fakeBackend.data.actions[0])
        for (const phase of ["failed", "cancelled", "interrupted", "completed"]) {
            item.submit()
            fakeBackend.applyFinished(true, {jobId:phase})
            report(phase, "running")
            verify(item.draft.pending)
            verify(item.editing !== null)
            report(phase, phase, "Result: " + phase)
            verify(!item.draft.pending)
            if (phase !== "completed") {
                compare(item.values.device, "old-device")
                compare(item.draft.error, "Result: " + phase)
            }
        }
        compare(item.editing, null)
        compare(item.values, {})
    }
    function test_navigation_restores_non_secret_draft() {
        const item = createTemporaryObject(view, test)
        item.begin({key:"unlock",label:"Unlock",confirm:"",fields:[
            {key:"folder",label:"Folder",value:"/original",options:[],secret:false},
            {key:"password",label:"Password",value:"",options:[],secret:true}
        ]})
        item.draft.setValue("folder", "/edited")
        item.draft.setValue("password", "secret")
        fakeBackend.active = false
        compare(item.values.password, "")
        item.destroy()
        wait(0)
        fakeBackend.active = true
        const restored = createTemporaryObject(view, test)
        compare(restored.values.folder, "/edited")
        compare(restored.values.password, "")
        verify(restored.draft.secretsCleared)
    }
    function test_submit_clears_password_and_blocks_duplicate_write() {
        const item = createTemporaryObject(view, test)
        item.begin({key:"unlock",label:"Unlock",confirm:"",fields:[{key:"password",label:"Password",value:"",options:[],secret:true}]})
        item.draft.setValue("password", "secret")
        item.submit()
        compare(fakeBackend.request.password, "secret")
        compare(item.values.password, "")
        compare(findChild(item, "operationField_password").text, "")
        fakeBackend.request = null
        item.submit()
        compare(fakeBackend.request, null)
    }
    function test_review_changed_target_requires_explicit_resubmission() {
        const item = createTemporaryObject(view, test)
        item.begin(fakeBackend.data.actions[0])
        const operation = {key:"eject",label:"Eject",confirm:"Review new drive",fields:[
            {key:"device",label:"Device",value:"new-device",options:[{value:"new-device",label:"New drive"}],secret:false}
        ]}
        fakeBackend.data = Object.assign({}, fakeBackend.data, {revision:"new",actions:[operation]})
        item.submit()
        compare(fakeBackend.request, null)
        item.draft.review()
        compare(fakeBackend.request, null)
        compare(item.values.device, "new-device")
        compare(item.editing.confirm, "Review new drive")
        item.submit()
        compare(fakeBackend.stamp, "new")
        compare(fakeBackend.request.device, "new-device")
    }
    function test_job_cancellation_uses_captured_identity() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {job:{id:"job-1",label:"Scan",phase:"running",message:"",cancellable:true}})
        const item = createTemporaryObject(view, test)
        button(item, "Cancel operation").clicked()
        compare(fakeBackend.cancelled, "job-1")
    }
}
