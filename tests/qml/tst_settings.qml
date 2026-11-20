import QtQuick
import QtTest
import QtQuick.Controls.Basic
import "../../defaults/quickshell/Components"
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Services"
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog

TestCase {
    id: test
    name: "Settings"
    when: windowShown
    visible: true
    width: 1040
    height: 760

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
    QtObject {
        id: fakeBackend
        property bool ready: true
        property bool busy: false
        property string error: ""
        property bool systemPending: false
        property bool syncAvailable: true
        property bool syncing: false
        property string syncState: "idle"
        property string syncMessage: ""
        property string pendingDescription: "Folder colors need updating."
        property int syncRequests: 0
        property int writes: 0
        property int selected: 0
        property bool rejectChanges: false
        function choices(id) { return ["First", "Second"] }
        function selection(id) { return selected }
        function apply(id, index) { writes++; if (!rejectChanges) selected = index }
        function refresh() { }
        function syncSystem() { syncRequests++ }
    }
    SettingsContent {
        id: content
        anchors.fill: parent
        theme: test.palette
        appearance: fakeBackend
        displays: fakeDisplays
    }
    QtObject {
        id: fakeDisplays
        property bool ready: true
        property bool busy: false
        property bool loaded: true
        property string error: ""
        property var presets: []
        property var nightLight: fakeNightLight
        property var colorProfiles: [{id:"rgb",name:"Studio RGB",path:"/test/rgb.icc",available:true}]
        property var monitor: ({ colorProfile: "" })
        property string colorAction: ""
        function assignColorProfile(id) { colorAction = id; monitor = {colorProfile:id === "none" ? "" : "/test/rgb.icc"} }
        function deleteColorProfile(id) { colorAction = "delete:" + id }
        property string lastPreset: ""
        function savePreset(name) { lastPreset = "save:" + name }
        function restorePreset(id) { lastPreset = "restore:" + id }
        function deletePreset(id) { lastPreset = "delete:" + id }
        property var monitors: [{ name: "eDP-1" }, { name: "DP-3" }]
        property string selectedConnector: "eDP-1"
        property string details: "2880 × 1800 · Active scale 150%"
        property string savedScaleNotice: ""
        property bool previewPending: false
        property bool applying: false
        property int previewSeconds: 20
        property string previewMessage: "Keep this display mode?"
        property int previewDecision: -1
        function finishPreview(keep) { previewDecision = keep ? 1 : 0; previewPending = false }
        property int writes: 0
        property int selected: 2
        property int selectedPosition: 0
        property string lastSetting: ""
        property bool canSelect: !busy
        property bool brightnessAvailable: true
        property bool brightnessHeld: false
        property real brightnessValue: 60
        function label(row) { return row.name }
        function selectDisplay(index) { selectedConnector = monitors[index].name }
        function canApply(id) {
            if (id === "brightness") return brightnessAvailable
            return id !== "arrangement" || (selectedConnector === "DP-3" && monitors.length > 1)
        }
        function description(id) { return id === "arrangement" && !canApply(id) ? "Select an external display." : "" }
        function choices(id) { return id === "arrangement" ? ["Automatic", "Left", "Right", "Above", "Below"] : ["Automatic", "100%", "150%"] }
        function selection(id) { return id === "arrangement" ? selectedPosition : selected }
        function value(id) { return brightnessAvailable ? brightnessValue : -1 }
        function adjust(id, value) { writes++; lastSetting = id; brightnessValue = value }
        function hold(id, pressed) { brightnessHeld = pressed }
        function apply(id, index) {
            writes++; lastSetting = id
            if (id === "arrangement") selectedPosition = index
            else if (id === "brightness") brightnessValue = index
            else selected = index
        }
        function refresh() { }
    }
    QtObject {
        id: fakeNightLight
        property bool ready: true
        property bool available: true
        property bool busy: false
        property string revision: "initial"
        property string error: ""
        property string description: "Off"
        property var preferences: ({mode:"off",temperature:4500,start:"21:00",end:"07:00"})
        property var saved: null
        function apply(mode, temperature, start, end) { saved = {mode:mode,temperature:temperature,start:start,end:end} }
        function retry() { }
    }
    SignalSpy { id: closeSpy; target: content; signalName: "closeRequested" }

    function init() {
        fakeBackend.ready = true
        fakeBackend.busy = false
        fakeBackend.writes = 0
        fakeBackend.selected = 0
        fakeBackend.rejectChanges = false
        fakeBackend.error = ""
        fakeBackend.systemPending = false
        fakeBackend.syncAvailable = true
        fakeBackend.syncing = false
        fakeBackend.syncState = "idle"
        fakeBackend.syncMessage = ""
        fakeBackend.syncRequests = 0
        content.selectedPage = "appearance"
        findChild(content, "settingsSearch").text = ""
        closeSpy.clear()
        fakeDisplays.ready = true
        fakeDisplays.busy = false
        fakeDisplays.monitors = [{ name: "eDP-1" }, { name: "DP-3" }]
        fakeDisplays.selectedConnector = "eDP-1"
        fakeDisplays.selected = 2
        fakeDisplays.writes = 0
        fakeDisplays.selectedPosition = 0
        fakeDisplays.lastSetting = ""
        fakeDisplays.brightnessAvailable = true
        fakeDisplays.brightnessHeld = false
        fakeDisplays.brightnessValue = 60
        fakeDisplays.previewPending = false
        fakeDisplays.previewDecision = -1
        fakeDisplays.presets = []
        fakeDisplays.lastPreset = ""
        wait(0)
    }

    Component {
        id: escapeFieldFactory
        ControlTextField {
            theme: test.palette
            property int cancellations: 0
            Keys.onEscapePressed: event => { cancellations++; clear(); event.accepted = true }
        }
    }
    Component {
        id: plainFieldFactory
        SettingsTextField { theme: test.palette }
    }
    Component {
        id: numberFactory
        SettingsNumberField { theme: test.palette; value: "42"; label: "Test"; minimum: 1; maximum: 100 }
    }
    Component { id: areaFactory; SettingsTextArea { theme: test.palette } }
    function test_cache_search_aliases() {
        for (const alias of ["cache", "disk space", "clean up", "paccache"])
            verify(Catalog.searchSettings(alias).some(row => row.id === "disk-usage"))
    }

    function test_escape_reaches_inner_password_handler() {
        const field = createTemporaryObject(escapeFieldFactory, content)
        field.text = "half typed password"
        field.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(field.cancellations, 1)
        compare(field.text, "")
        compare(closeSpy.count, 0)
    }
    function test_escape_plain_and_numeric_fields() {
        for (const factory of [plainFieldFactory, numberFactory, areaFactory]) {
            const editor = createTemporaryObject(factory, content)
            const field = factory === numberFactory ? findChild(editor, "numberText") : editor
            field.text = "42"
            field.forceActiveFocus()
            keyClick(Qt.Key_Escape)
            compare(field.text, "")
            compare(closeSpy.count, 0)
            keyClick(Qt.Key_Escape)
            verify(!field.activeFocus)
            compare(closeSpy.count, 0)
            keyClick(Qt.Key_Escape)
            compare(closeSpy.count, 1)
            closeSpy.clear()
            editor.destroy()
        }
    }
    function test_escape_popup_first() {
        const choice = findChild(content, "settingsChoice_theme")
        choice.forceActiveFocus()
        choice.popup.open()
        tryCompare(choice.popup, "visible", true)
        keyClick(Qt.Key_Escape)
        tryCompare(choice.popup, "visible", false)
        compare(closeSpy.count, 0)
    }

    QtObject {
        id: wifiBackend
        signal credentialsRequired(string key)
        property bool profilesActive: true
        property bool available: true
        property bool busy: false
        property bool enabled: true
        property bool hardwareEnabled: true
        property bool managed: true
        property bool hosting: false
        property bool profilesBusy: false
        property bool profilesReady: true
        property bool usable: true
        property var wifiDevice: ({})
        property var connectedWifiNetwork: null
        property var wifiRows: [{key:"test", ssid:"Test", known:false, security:"wpa2", connected:false, stateChanging:false, strength:80}]
        property var profiles: []
        property string profilesError: ""
        property string failureReason: ""
        property string actionKey: ""
        function requiresCredentials(security) { return true }
        function supportsPassword(security) { return true }
    }
    Component { id: wifiFactory; SettingsWifi { theme: test.palette; backend: wifiBackend; width: 600 } }
    function test_escape_real_wifi_password_form() {
        const form = createTemporaryObject(wifiFactory, content)
        form.requestConnect(wifiBackend.wifiRows[0])
        const password = findChild(form, "wifiPassword")
        password.text = "half typed password"
        verify(password.activeFocus)
        keyClick(Qt.Key_Escape)
        compare(form.passwordKey, "")
        compare(password.text, "")
        compare(closeSpy.count, 0)
    }
    QtObject {
        id: operationBackend
        signal applyFinished(bool success, var result)
        property bool ready: true
        property bool writable: true
        property bool busy: false
        property bool writing: false
        property bool active: true
        property string error: ""
        property var data: ({revision:"test", actions:[], details:[], message:"", job:null})
        property SettingsOperationDraft draft: SettingsOperationDraft { backend: operationBackend }
    }
    Component { id: operationFactory; SettingsOperations { theme: test.palette; settingId: "accounts"; backend: operationBackend; width: 600 } }
    function test_escape_real_account_form() {
        const form = createTemporaryObject(operationFactory, content)
        form.begin({key:"account", label:"Account", confirm:"", fields:[{key:"password", label:"Password", value:"", options:[], secret:true}]})
        wait(0)
        const field = findChild(form, "operationField_password")
        verify(field !== null)
        field.forceActiveFocus()
        keyClick(Qt.Key_P)
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_S)
        verify(operationBackend.draft.values.password.length > 0)
        keyClick(Qt.Key_Escape)
        compare(field.text, "")
        compare(operationBackend.draft.values.password, "")
        compare(closeSpy.count, 0)
        keyClick(Qt.Key_Escape)
        verify(!field.activeFocus)
        keyClick(Qt.Key_Escape)
        compare(form.editing, null)
        compare(closeSpy.count, 0)
    }

    function test_search_and_empty_state() {
        var search = findChild(content, "settingsSearch")
        search.text = "microphone"
        compare(content.searchResults[0].pageId, "sound")
        search.text = "backup retention"
        compare(content.searchResults[0].id, "backup")
        search.text = "no-match-12345"
        verify(content.searching)
        compare(content.searchResults.length, 0)
        search.text = ""
        compare(content.results.length, 10)
    }

    function test_search_jumps_to_exact_setting() {
        const search = findChild(content, "settingsSearch")
        search.text = "backup retention"
        content.focusSearch()
        keyClick(Qt.Key_Return)
        compare(search.text, "")
        compare(content.page.id, "storage")
        tryCompare(content, "highlightedSetting", "backup")
        const target = findChild(content, "settingTarget_backup")
        verify(target !== null)
        tryVerify(() => target.activeFocus)
        const scroll = findChild(content, "settingsPageScroll")
        verify(scroll.contentItem.contentY > 0)
        const y = target.mapToItem(scroll, 0, 0).y
        verify(y >= -1 && y < scroll.height, "Search target should be in view")
        compare(fakeBackend.writes, 0)
    }
    function test_search_keyboard_results_and_escape() {
        const search = findChild(content, "settingsSearch")
        search.text = "timezone"
        content.focusSearch()
        keyClick(Qt.Key_Down)
        verify(findChild(content, "searchResult_datetime").activeFocus)
        keyClick(Qt.Key_Up)
        verify(search.activeFocus)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(content.page.id, "system")
        compare(content.highlightedSetting, "datetime")
    }
    function test_search_vocabulary_data() {
        return [
            {query:"repeat delay", row:"layouts"}, {query:"caps", row:"layouts"},
            {query:"compose", row:"layouts"}, {query:"secondary click", row:"pointer"},
            {query:"wifi", row:"wifi"}, {query:"trackpad", row:"pointer"},
            {query:"dnd", row:"dnd"}, {query:"browser", row:"defaults"},
            {query:"font", row:"fonts"}, {query:"cursor", row:"cursor"},
            {query:"suspend", row:"screen-off"}, {query:"autostart", row:"startup"},
            {query:"night shift", row:"night-light"}, {query:"scale", row:"scale"},
            {query:"Wi-Fi", row:"wifi"}, {query:"  WI  FI! ", row:"wifi"},
            {query:"nightlight", row:"night-light"}, {query:"night light", row:"night-light"},
            {query:"blue light", row:"night-light"}, {query:"backup retention", row:"backup"},
            {query:"default apps", row:"defaults"}, {query:"login items", row:"startup"},
            {query:"typeface", row:"fonts"}, {query:"sleep", row:"screen-off"},
            {query:"hidpi", row:"scale"}, {query:"dark mode", row:"mode"},
            {query:"background", row:"wallpaper"}, {query:"speaker", row:"output"},
            {query:"microphone", row:"input"}, {query:"bluetooth", row:"bluetooth"},
            {query:"vpn", row:"vpn"}, {query:"tethering", row:"hotspot"},
            {query:"charge limit", row:"battery-health"}, {query:"hotkeys", row:"shortcuts"},
            {query:"upgrade", row:"updates"}, {query:"accounts", row:"accounts"},
            {query:"zzxqv nonsense", row:null}, {query:"ailscale", row:"vpn"}
        ].map(entry => ({tag:entry.query, query:entry.query, row:entry.row}))
    }
    function test_search_vocabulary(data) {
        const results = Catalog.searchSettings(data.query)
        if (data.row === null) compare(results.length, 0)
        else { verify(results.length > 0); compare(results[0].id, data.row) }
    }
    function test_every_row_has_aliases() {
        for (const page of Catalog.pages)
            for (const group of page.groups)
                for (const row of group.rows) verify(row.aliases.length > 0, row.id)
        verify(!Catalog.searchSettings("scale").some(row => row.id === "vpn"))
        const first = Catalog.searchSettings("text size").map(row => row.id).join(",")
        compare(Catalog.searchSettings("text size").map(row => row.id).join(","), first)
    }
    function test_display_confirmation_helper() {
        content.selectedPage = "displays"
        wait(0)
        for (const id of ["resolution", "mirroring", "display-presets"])
            verify(findChild(content, "settingsHelper_" + id).text.includes("20 seconds"))
    }

    function test_search_aliases_and_row_scoping() {
        compare(Catalog.searchSettings("time zone")[0].id, "datetime")
        compare(Catalog.searchSettings("screen reader")[0].id, "assistive")
        compare(Catalog.searchSettings("uninstall")[0].id, "installed")
        compare(Catalog.searchSettings("   ").length, 0)
        compare(Catalog.searchSettings("firmware sign-in").length, 0)
        compare(Catalog.searchSettings("DeSkToP ThEmE")[0].id, "theme")
    }
    function test_guidance_opens_exact_setting_without_writing() {
        content.openSetting("backup")
        compare(content.page.id, "storage")
        const target = findChild(content, "settingTarget_backup")
        tryVerify(() => target.activeFocus)
        compare(content.highlightedSetting, "backup")
        compare(fakeBackend.writes, 0)
        content.openSetting("missing-setting")
        compare(content.page.id, "storage")
    }
    function test_search_mouse_selection_at_minimum_window_size() {
        const oldWidth = test.width
        const oldHeight = test.height
        try {
            test.width = 640; test.height = 480
            findChild(content, "settingsSearch").text = "backup retention"
            wait(20)
            mouseClick(findChild(content, "searchResult_backup"))
            compare(content.page.id, "storage")
            const target = findChild(content, "settingTarget_backup")
            tryVerify(() => target.activeFocus)
            const scroll = findChild(content, "settingsPageScroll")
            const y = target.mapToItem(scroll, 0, 0).y
            verify(y >= -1 && y < scroll.height)
            compare(fakeBackend.writes, 0)
        } finally { test.width = oldWidth; test.height = oldHeight }
    }

    function test_display_controls_route_to_selected_backend() {
        content.selectedPage = "displays"
        wait(20)
        var display = findChild(content, "settingsDisplaySelector")
        var scale = findChild(content, "settingsChoice_scale")
        verify(display !== null && scale !== null)
        verify(display.enabled && scale.enabled)
        compare(scale.currentIndex, 2)
        display.activated(1)
        compare(fakeDisplays.selectedConnector, "DP-3")
        compare(display.currentIndex, 1)
        scale.activated(0)
        compare(fakeDisplays.writes, 1)
        compare(fakeBackend.writes, 0)
        compare(scale.currentIndex, 0)
        fakeDisplays.busy = true
        verify(!display.enabled && !scale.enabled)
        fakeDisplays.busy = false
        fakeDisplays.ready = false
        fakeDisplays.monitors = []
        verify(!display.enabled && !scale.enabled)
        compare(findChild(content, "displayStatus").text, "No connected displays.")
    }

    function test_position_availability_and_routing() {
        content.selectedPage = "displays"
        wait(20)
        var position = findChild(content, "settingsChoice_arrangement")
        var scale = findChild(content, "settingsChoice_scale")
        verify(position !== null && !position.enabled)
        verify(scale.enabled)
        compare(findChild(content, "settingsDescription_arrangement").text, "Select an external display.")
        findChild(content, "settingsDisplaySelector").activated(1)
        verify(position.enabled)
        position.activated(3)
        compare(fakeDisplays.lastSetting, "arrangement")
        compare(position.currentIndex, 3)
        compare(scale.currentIndex, 2)
        fakeDisplays.busy = true
        verify(!position.enabled)
        fakeDisplays.busy = false
        fakeDisplays.monitors = [{ name: "DP-3" }]
        verify(!position.enabled)
        verify(scale.enabled)
        compare(fakeDisplays.writes, 1)
    }

    function test_brightness_slider_keyboard_and_availability() {
        content.selectedPage = "displays"
        wait(20)
        var slider = findChild(content, "settingsSlider_brightness")
        verify(slider !== null && slider.enabled)
        compare(slider.value, 60)
        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(fakeDisplays.lastSetting, "brightness")
        compare(fakeDisplays.brightnessValue, 61)
        fakeDisplays.brightnessValue = 35
        compare(slider.value, 35)
        fakeDisplays.brightnessAvailable = false
        verify(!slider.enabled)
        var writes = fakeDisplays.writes
        keyClick(Qt.Key_Right)
        compare(fakeDisplays.writes, writes)
    }

    function test_brightness_drag_releases_backend_on_page_change() {
        content.selectedPage = "displays"
        wait(20)
        var slider = findChild(content, "settingsSlider_brightness")
        mousePress(slider, slider.width / 2, slider.height / 2)
        verify(fakeDisplays.brightnessHeld)
        content.selectedPage = "appearance"
        wait(20)
        verify(!fakeDisplays.brightnessHeld)
        mouseRelease(content, 10, 10)
        compare(fakeBackend.writes, 0)
    }

    function test_pages_at_narrow_width() {
        test.width = 640
        for (var i = 0; i < Catalog.pages.length; i++) {
            content.selectedPage = Catalog.pages[i].id
            wait(20)
            compare(content.page.id, Catalog.pages[i].id)
            verify(findChild(content, "settingsPageScroll").contentWidth > 0)
        }
        compare(fakeBackend.writes, 0)
        test.width = 1040
    }

    function test_keyboard_search_and_escape() {
        var search = findChild(content, "settingsSearch")
        content.focusSearch()
        verify(search.activeFocus)
        search.text = "firmware"
        compare(content.searchResults[0].id, "firmware")
        keyClick(Qt.Key_Escape)
        compare(search.text, "")
        compare(closeSpy.count, 0)
        // The search field is the window's resting focus: once it is empty,
        // the next Escape closes the window rather than only blurring it.
        keyClick(Qt.Key_Escape)
        compare(closeSpy.count, 1)
    }

    Component {
        id: rowFactory
        SettingsRow {
            width: 600
            theme: test.palette
            backend: fakeBackend
        }
    }

    function test_missing_service_never_writes() {
        var row = createTemporaryObject(rowFactory, test, {
            setting: { id: "profile", title: "Power profile", description: "Unavailable", kind: "choice" }
        })
        verify(row !== null)
        compare(row.live, false)
        compare(row.writable, false)
        compare(fakeBackend.writes, 0)
    }

    function test_live_controls_wait_for_backend() {
        var row = createTemporaryObject(rowFactory, test, {
            setting: { id: "mode", title: "Color mode", description: "Live", kind: "choice", live: true }
        })
        verify(row.live)
        verify(row.writable)
        fakeBackend.busy = true
        verify(!row.writable)
        fakeBackend.busy = false
        fakeBackend.ready = false
        verify(!row.writable)
        fakeBackend.ready = true
        fakeBackend.selected = 1
        compare(row.selection, 1)
    }

    function test_failed_apply_keeps_confirmed_selection() {
        var row = createTemporaryObject(rowFactory, test, {
            setting: { id: "mode", title: "Color mode", description: "Live", kind: "choice", live: true }
        })
        var choice = findChild(row, "settingsChoice_mode")
        verify(choice !== null)
        fakeBackend.rejectChanges = true
        choice.currentIndex = 1
        choice.activated(1)
        compare(fakeBackend.writes, 1)
        compare(choice.currentIndex, 0)
        fakeBackend.selected = 1
        compare(choice.currentIndex, 1)
    }

    Component {
        id: comboFactory
        SettingsComboBox {
            theme: test.palette
            model: ["Dark", "Light"]
        }
    }

    function test_night_light_controls() {
        content.selectedPage = "displays"
        wait(0)
        var mode = findChild(content, "nightLightMode")
        var temperature = findChild(content, "nightLightTemperature")
        var apply = findChild(content, "applyNightLight")
        compare(mode.currentIndex, 0)
        verify(!temperature.enabled)
        mode.currentIndex = 2
        temperature.currentIndex = 2
        findChild(content, "nightLightStart").text = "22:15"
        findChild(content, "nightLightEnd").text = "06:45"
        apply.clicked()
        compare(fakeNightLight.saved.mode, "schedule")
        compare(fakeNightLight.saved.temperature, 3500)
        compare(fakeNightLight.saved.start, "22:15")
        fakeNightLight.busy = true
        verify(!apply.enabled)
        fakeNightLight.busy = false
        fakeNightLight.available = false
        verify(!apply.enabled)
        mode.currentIndex = 0
        verify(apply.enabled)
        fakeNightLight.available = true
    }

    function test_color_profile_controls() {
        content.selectedPage = "displays"
        wait(0)
        var choice = findChild(content, "displayColorProfile")
        compare(choice.currentIndex, 0)
        choice.activated(1)
        compare(fakeDisplays.colorAction, "rgb")
        compare(choice.currentIndex, 1)
        fakeDisplays.busy = true
        verify(!choice.enabled && !findChild(content, "importColorProfile").enabled)
        fakeDisplays.busy = false
        choice.activated(0)
        compare(fakeDisplays.colorAction, "none")
        compare(choice.currentIndex, 0)
    }

    function test_saved_setup_controls() {
        content.selectedPage = "displays"
        wait(0)
        var field = findChild(content, "displaySetupName")
        var save = findChild(content, "saveDisplaySetup")
        verify(!save.enabled)
        field.text = "Desk"
        verify(save.enabled)
        save.clicked()
        compare(fakeDisplays.lastPreset, "save:Desk")
        fakeDisplays.presets = [{id:"desk",name:"Desk",available:false,reason:"Connect both displays",summary:"2 displays"}]
        wait(0)
        var restore = findChild(content, "restoreDisplaySetup_desk")
        var remove = findChild(content, "deleteDisplaySetup_desk")
        verify(!restore.enabled && remove.enabled)
        remove.clicked()
        compare(fakeDisplays.lastPreset, "save:Desk")
        compare(remove.text, "Delete “Desk”")
        remove.clicked()
        compare(fakeDisplays.lastPreset, "delete:desk")
        fakeDisplays.presets = [{id:"desk",name:"Desk",available:true,reason:"",summary:"2 displays"}]
        wait(0)
        restore = findChild(content, "restoreDisplaySetup_desk")
        verify(restore.enabled)
        restore.clicked()
        compare(fakeDisplays.lastPreset, "restore:desk")
        fakeDisplays.busy = true
        verify(!save.enabled && !restore.enabled)
    }

    function test_display_mode_confirmation() {
        content.selectedPage = "displays"
        wait(0)
        var scroll = findChild(content, "settingsPageScroll")
        scroll.contentItem.contentY = 250
        fakeDisplays.previewPending = true
        compare(scroll.contentItem.contentY, 0)
        var keep = findChild(content, "keepDisplayMode")
        var revert = findChild(content, "revertDisplayMode")
        verify(keep.visible && keep.enabled)
        mouseClick(keep)
        compare(fakeDisplays.previewDecision, 1)
        fakeDisplays.previewPending = true
        fakeDisplays.previewSeconds = 0
        verify(!keep.enabled && revert.enabled)
        mouseClick(revert)
        compare(fakeDisplays.previewDecision, 0)
        fakeDisplays.previewSeconds = 20
    }

    function test_dropdown_tracks_theme_while_open() {
        var combo = createTemporaryObject(comboFactory, test, { x: 400, y: 100 })
        verify(combo !== null)
        var original = test.palette
        try {
            combo.popup.open()
            tryCompare(combo.popup, "opened", true)
            compare(combo.popup.background.color, original.panelSurface)
            compare(combo.contentItem.color, original.text)
            tryVerify(function() { return combo.popup.contentItem.itemAtIndex(1) !== null })
            var option = combo.popup.contentItem.itemAtIndex(1)
            compare(option.contentItem.color, original.text)

            test.palette = Object.assign({}, original, {
                panelSurface: "#f4faf7", surfaceRaised: "#e7f1ec",
                text: "#123329", textMuted: "#526e63", accentBright: "#007c60",
                accentSurface: "#d3ebe2", outline: "#b8d4c7"
            })
            compare(combo.popup.background.color, test.palette.panelSurface)
            compare(combo.contentItem.color, test.palette.text)
            compare(option.contentItem.color, test.palette.text)
            test.palette = original
            compare(combo.popup.background.color, original.panelSurface)
            compare(option.contentItem.color, original.text)
            combo.enabled = false
            compare(combo.contentItem.color, original.textMuted)
            compare(combo.indicator.color, original.textMuted)
        } finally {
            combo.popup.close()
            test.palette = original
        }
    }

    function test_dropdown_keyboard_selection() {
        var combo = createTemporaryObject(comboFactory, test, { x: 400, y: 100 })
        combo.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(combo.popup, "opened", true)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(combo.currentIndex, 1)
        tryCompare(combo.popup, "opened", false)
    }

    function test_system_appearance_requires_explicit_action() {
        fakeBackend.systemPending = true
        var button = findChild(content, "applySystemAppearance")
        verify(button.visible)
        verify(button.enabled)
        compare(fakeBackend.syncRequests, 0)
        mouseClick(button)
        compare(fakeBackend.syncRequests, 1)
        fakeBackend.busy = true
        verify(!button.enabled)
        fakeBackend.busy = false
        fakeBackend.syncAvailable = false
        verify(!button.enabled)
        fakeBackend.systemPending = false
        fakeBackend.syncMessage = "System appearance is up to date."
        verify(!button.visible)
        compare(findChild(content, "systemAppearanceProgress").text, fakeBackend.syncMessage)
    }
}
