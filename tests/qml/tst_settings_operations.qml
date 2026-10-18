import QtQuick
import QtTest
import "../../defaults/quickshell/Settings/OperationActions.js" as Actions
import "../../defaults/quickshell/Services"
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog
TestCase {
    id: test
    name: "SettingsOperations"
    width: 600; height: 800
    when: windowShown
    visible: true
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
        property string dismissedJobId: ""
        function apply(value, revision) { request = value; stamp = revision }
        function refresh(clear) { error = "" }
        function cancelJob(id) { cancelled = id }
    }
    Component { id: view; SettingsOperations { theme: test.themePalette; settingId: "drives"; backend: fakeBackend } }
    SignalSpy { id: navigationSpy; signalName: "settingRequested" }
    function button(parent, text) {
        if (parent.text === text && typeof parent.clicked === "function") return parent
        for (const child of parent.children || []) { const found = button(child, text); if (found) return found }
        return null
    }
    function init() {
        fakeBackend.draft.pending = false; fakeBackend.draft.discard(); fakeBackend.error = ""; fakeBackend.active = true
        fakeBackend.ready = true; fakeBackend.writable = true; fakeBackend.busy = false; fakeBackend.writing = false; fakeBackend.request = null; fakeBackend.cancelled = ""
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
        verify(!findChild(item, "moreOperations").enabled)
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
    function actions(rows) { fakeBackend.data = Object.assign({}, fakeBackend.data, {actions:rows}) }
    function action(key, fields, confirm) { return {key:key,label:key,fields:fields || [],confirm:confirm || "",cancellable:false} }
    function test_primary_read_runs_directly_but_input_action_opens_form() {
        actions([action("preview-cleanup"), action("scan", [{key:"folder",label:"Folder",value:"/home",options:[],secret:false}])])
        const item = createTemporaryObject(view, test, {settingId:"disk-usage",width:550})
        compare(findChild(item, "primaryOperation").text, "scan…")
        findChild(item, "primaryOperation").clicked()
        compare(item.editing.key, "scan")
        compare(fakeBackend.request, null)
        item.draft.discard()
        item.activate(fakeBackend.data.actions[0], "original")
        compare(fakeBackend.request.action, "preview-cleanup")
    }
    function test_one_drive_health_read_skips_picker_multiple_drives_do_not() {
        const target = {key:"device",label:"Drive",value:"disk-1",options:[{value:"disk-1",label:"Drive one"}],secret:false}
        actions([action("health", [target])])
        const item = createTemporaryObject(view, test, {settingId:"disk-health",width:550})
        findChild(item, "primaryOperation").clicked()
        compare(fakeBackend.request.device, "disk-1")
        item.draft.pending = false; item.draft.discard(); fakeBackend.request = null
        target.options.push({value:"disk-2",label:"Drive two"})
        actions([action("health", [target])])
        findChild(item, "primaryOperation").clicked()
        compare(fakeBackend.request, null)
        compare(item.editing.key, "health")
    }
    function test_mutations_and_unknown_actions_keep_confirmation_step() {
        verify(!Actions.direct("snapshots", action("create")))
        verify(!Actions.direct("backup", action("backup")))
        verify(!Actions.direct("updates", action("update", [], "Install updates?")))
        verify(!Actions.direct("updates", action("check", [], "Confirm network access")))
        verify(!Actions.direct("future-provider", action("read")))
        compare(Actions.primary("drives", [action("eject")]), null)
    }
    function test_secondary_menu_freezes_action_and_revision() {
        actions([action("scan", [{key:"folder",label:"Folder",value:"/home",options:[],secret:false}]), action("preview-cleanup")])
        const item = createTemporaryObject(view, test, {settingId:"disk-usage",width:550})
        findChild(item, "moreOperations").clicked()
        const menu = findChild(item, "operationActionsMenu")
        tryCompare(menu, "opened", true)
        compare(menu.count, 1)
        compare(menu.itemAt(0).text, "preview-cleanup")
        compare(menu.background.color, test.themePalette.panelSurface)
        const entry = menu.entries[0]
        fakeBackend.data = Object.assign({}, fakeBackend.data, {revision:"changed",actions:[action("cleanup", [], "Delete thumbnails?")]})
        menu.chosen(entry)
        compare(fakeBackend.request, null)
        verify(item.draft.stale)
        compare(item.editing.key, "preview-cleanup")
        menu.close()
    }
    function test_menu_keyboard_activation_and_busy_close() {
        actions([action("check"), action("release-notes")])
        const item = createTemporaryObject(view, test, {settingId:"updates",width:550})
        const more = findChild(item, "moreOperations")
        more.forceActiveFocus()
        keyClick(Qt.Key_Space)
        const menu = findChild(item, "operationActionsMenu")
        tryCompare(menu, "opened", true)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(fakeBackend.request.action, "release-notes")
        tryCompare(menu, "opened", false)
        item.draft.pending = false; item.draft.discard()
        more.clicked()
        tryCompare(menu, "opened", true)
        fakeBackend.writable = false
        verify(menu.opened) // A status poll must not dismiss a menu being read.
        fakeBackend.writing = true
        tryCompare(menu, "opened", false)
    }
    function test_dismissing_menu_never_starts_an_action() {
        const item = createTemporaryObject(view, test, {width:260})
        findChild(item, "moreOperations").clicked()
        const menu = findChild(item, "operationActionsMenu")
        tryCompare(menu, "opened", true)
        verify(menu.width <= item.width)
        keyClick(Qt.Key_Escape)
        tryCompare(menu, "opened", false)
        compare(fakeBackend.request, null)
        compare(item.editing, null)
    }
    function test_destructive_menu_action_still_requires_confirmation() {
        const item = createTemporaryObject(view, test, {width:550})
        findChild(item, "moreOperations").clicked()
        const menu = findChild(item, "operationActionsMenu")
        tryCompare(menu, "opened", true)
        menu.itemAt(0).triggered()
        compare(fakeBackend.request, null)
        compare(item.editing.confirm, "Eject this device?")
        button(item, "Eject").clicked()
        compare(fakeBackend.request.action, "eject")
        menu.close()
    }
    function test_guidance_navigation_is_not_a_backend_operation() {
        fakeBackend.data = Object.assign({}, fakeBackend.data, {actions:[],notices:[{
            kind:"not-configured",title:"Set up backups before restoring files",
            nextStep:"Open Scheduled file backups to configure a repository.",target:"backup"
        }]})
        const item = createTemporaryObject(view, test, {width:550})
        navigationSpy.target = item; navigationSpy.clear()
        const next = findChild(item, "capabilityNextStep")
        verify(next.visible)
        next.clicked()
        compare(navigationSpy.count, 1)
        compare(navigationSpy.signalArguments[0][0], "backup")
        compare(fakeBackend.request, null)
        compare(item.editing, null)
        navigationSpy.target = null
    }
}
