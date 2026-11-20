import QtQuick
import Quickshell
import "Services"
ShellRoot {
    id: root
    property int step: 0
    property string oldRevision: ""
    SettingsTask { id: backend; script: "unused"; helper: Qt.resolvedUrl("task.py").toString().replace("file://", "") }
    function seed(script, request, baseline, cancelled = false) {
        backend.script = script
        backend.pendingRequest = request
        backend.pendingBaseline = baseline
        backend.feedbackTarget = JSON.stringify([request.control || request.action || "value", request.id || request.app || ""])
        backend.pendingVersion = backend.outcomeVersions[backend.feedbackTarget] || 0
        backend.failure(JSON.stringify({error:{message:cancelled ? "Cancelled" : "Could not apply this change. Try again.",detail:cancelled ? "" : "Safe diagnostic",cancelled:cancelled}}))
    }
    function checkContracts() {
        const cases = [
            ["startup-settings.py", {action:"enable",id:"one",enabled:true}, {revision:"a",rows:[{id:"one",enabled:false}]}, {revision:"b",rows:[{id:"one",enabled:true}]}],
            ["startup-settings.py", {action:"reset",id:"one"}, {revision:"a",rows:[{id:"one",reset:true}]}, {revision:"b",rows:[{id:"one",reset:false}]}],
            ["wallpaper-settings.py", {action:"set",id:"one",path:"/tmp/one.png",fit:"crop"}, {revision:"a",rows:[{id:"one",path:"/tmp/two.png",current:"/tmp/two.png",custom:true,fit:"crop"}]}, {revision:"b",rows:[{id:"one",path:"/tmp/one.png",current:"/tmp/one.png",custom:true,fit:"crop"}]}],
            ["wallpaper-settings.py", {action:"reset",id:"one"}, {revision:"a",rows:[{id:"one",custom:true}]}, {revision:"b",rows:[{id:"one",custom:false,path:"/tmp/theme.png",current:"/tmp/theme.png"}]}],
            ["webapps-settings.py", {action:"remove",id:"one"}, {revision:"a",rows:[{id:"one"}]}, {revision:"b",rows:[]}],
            ["webapps-settings.py", {action:"create",name:"One",url:"https://example.com"}, {revision:"a",rows:[]}, {revision:"b",rows:[{id:"one",name:"One",url:"https://example.com"}]}],
            ["notification-settings.py", {action:"manual",value:true}, {revision:"a",paused:false,policy:{manual:false}}, {revision:"b",paused:true,policy:{manual:true}}],
            ["notification-settings.py", {action:"schedule",enabled:true,start:"22:00",end:"08:00"}, {revision:"a",policy:{schedule:false,start:"22:00",end:"08:00"}}, {revision:"b",policy:{schedule:true,start:"22:00",end:"08:00"}}],
            ["notification-settings.py", {action:"app",app:"Mail",blocked:true}, {revision:"a",apps:["Mail"],policy:{blocked:[]}}, {revision:"b",apps:["Mail"],policy:{blocked:["Mail"]}}],
            ["system-settings.py", {action:"diagnose"}, {revision:"a",report:null}, {revision:"b",report:{time:"new",text:"Report",code:0}}]
        ]
        for (const entry of cases) {
            seed(entry[0],entry[1],entry[2])
            const key = backend.feedbackTarget
            backend.reconcile(Object.assign({},entry[2],{revision:"unrelated",notice:"Poll"}))
            check(Boolean(backend.outcomes[key]))
            backend.reconcile(entry[3]); check(!backend.outcomes[key])
            if (entry[1].id || entry[1].app) {
                seed(entry[0],entry[1],entry[2])
                backend.reconcile({revision:"removed",rows:[],apps:[],policy:{blocked:[]}})
                check(!backend.outcomes[key])
            }
        }
        seed("startup-settings.py",{action:"enable",id:"one",enabled:true},{rows:[{id:"one",enabled:false}]})
        seed("startup-settings.py",{action:"enable",id:"two",enabled:true},{rows:[{id:"two",enabled:false}]})
        backend.clearOutcome("enable","one")
        check(backend.outcome("enable","one") === null && backend.outcome("enable","two") !== null)
        backend.clearOutcome("enable","two")
        seed("startup-settings.py",{action:"enable",id:"one",enabled:true},{rows:[{id:"one",enabled:false}]})
        backend.clearOutcome("enable","one")
        backend.failure(JSON.stringify({error:{message:"Late failure",detail:""}}))
        check(backend.outcome("enable","one") === null)
    }
    function check(value) { if (!value) throw new Error("Task backend step " + step) }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (root.step++) {
                case 0: root.check(!backend.ready); backend.active = true; break
                case 1:
                    root.check(backend.writable && !backend.data.value)
                    root.oldRevision = backend.data.revision
                    backend.apply({value: true}); root.check(backend.busy && !backend.data.value); backend.active = false; break
                case 2: root.check(backend.data.value); backend.apply({value: false}, root.oldRevision); break
                case 3:
                    root.check(backend.error.includes("changed") && backend.errorDetail === "Revision mismatch." && backend.data.value)
                    backend.apply({cancel: true}); break
                case 4:
                    root.check(backend.cancelled && backend.error === "Cancelled" && backend.data.value)
                    backend.apply({value: false}); break
                case 5:
                    root.check(!backend.data.value && backend.error === "" && !backend.cancelled)
                    root.checkContracts()
                    root.seed("startup-settings.py",{action:"enable",id:"one",enabled:true},{rows:[{id:"one",enabled:false}]},true)
                    break
                case 6:
                    if (backend.outcome("enable","one")) { root.check(backend.outcome("enable","one").cancelled); root.step--; break }
                    backend.helper = "/missing/helper.py"; backend.refresh(true); break
                case 7: root.check(!backend.ready && !backend.writable); console.log("SETTINGS_TASK_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
