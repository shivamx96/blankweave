import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Settings/JobStatus.js" as Status

TestCase {
    id: test
    name: "SettingsJobs"
    when: windowShown
    visible: true
    width: 600; height: 500
    property var colors: ({text:"#eeeeee",textMuted:"#aaaaaa",surfaceRaised:"#223344",surfaceHover:"#334455",surfacePressed:"#445566",
        accentSurface:"#334455",accentBright:"#77aaff",outline:"#445566",warning:"#ffaa33",
        fontFamily:"sans-serif",smallTextSize:12,textSize:13,widgetRadius:4,reducedMotion:true})
    Component { id: factory; SettingsJobReport { theme: test.colors; width: 550 } }
    SignalSpy { id: copySpy; signalName:"copyRequested" }
    SignalSpy { id: dismissSpy; signalName:"dismissRequested" }
    function button(parent, text) {
        if (parent.text === text && typeof parent.clicked === "function") return parent
        for (const child of parent.children || []) { const found = button(child, text); if (found) return found }
        return null
    }
    function job(phase) { return {id:"one",label:"Scan directory",phase:phase,message:"line\n".repeat(1000),started:"2026-10-18T10:00:00Z",finished:"2026-10-18T10:01:05Z"} }
    function test_report_is_collapsed_and_bounded() {
        const view = createTemporaryObject(factory, test, {job:job("completed")})
        verify(!findChild(view, "jobDetails").visible)
        verify(view.implicitHeight < 160)
        button(view, "View details").clicked()
        verify(findChild(view, "jobDetails").visible)
        tryVerify(() => findChild(view, "jobDetails").height <= 180)
        view.job = Object.assign({}, job("completed"), {id:"two"})
        verify(!view.expanded)
    }
    function test_copy_and_dismiss_capture_exact_report() {
        const view = createTemporaryObject(factory, test, {job:job("failed")})
        copySpy.target = view; copySpy.clear(); dismissSpy.target = view; dismissSpy.clear()
        button(view, "Copy report").clicked()
        compare(copySpy.count, 1)
        compare(copySpy.signalArguments[0][0], "Scan directory · Failed\n" + view.job.message)
        button(view, "Dismiss").clicked()
        compare(dismissSpy.signalArguments[0][0], "one")
        copySpy.target = null; dismissSpy.target = null
    }
    function test_running_report_cannot_be_dismissed() {
        const view = createTemporaryObject(factory, test, {job:job("running")})
        verify(!button(view, "Dismiss").visible)
        verify(findChild(view, "jobSummary").text.includes("Running"))
    }
    function test_elapsed_stops_at_finish_and_legacy_reports_are_honest() {
        compare(Status.elapsed(job("completed"), Date.now()), "1m 5s")
        compare(Status.elapsed(job("running"), Date.parse("2026-10-18T10:02:00Z")), "2m 0s")
        compare(Status.elapsed({started:job("running").started,phase:"completed"}, Date.now()), "")
        compare(Status.elapsed({started:"invalid",phase:"running"}, Date.now()), "")
        compare(Status.phase(job("interrupted")), "Interrupted")
    }
}
