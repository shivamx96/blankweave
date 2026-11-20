import QtQuick
import "../Components/BarScroll.js" as BarScroll

// Intent only: no subscriptions to audio or display level changes.
QtObject {
    id: root
    required property var audio
    property string focusedScreenName: ""
    property bool blocked: false
    property bool open: false
    property string screenName: ""
    property string kind: ""
    property string label: ""
    property string icon: ""
    property real level: 0
    property var panels: []
    readonly property bool visible: open && !blocked && !panels.some(p => p.kind === kind)
    property Timer expiry: Timer { interval: 1500; onTriggered: root.open = false }
    function panel(owner, kind, open) {
        panels = panels.filter(p => p.owner !== owner).concat(open ? [{owner: owner, kind: kind}] : [])
        if (open && root.kind === kind) root.open = false
    }
    function show(kind, label, icon, level) {
        root.kind = kind; root.label = label; root.icon = icon
        root.level = Math.max(0, Math.min(1, level))
        screenName = focusedScreenName
        open = !blocked && !panels.some(p => p.kind === kind)
        expiry.restart()
    }
    onBlockedChanged: if (blocked) open = false
    function volume(action, steps = 1) {
        if (!audio.available) return
        let muted = audio.muted
        let level = audio.volume
        if (action === "mute") { muted = !muted; audio.setOutputMuted(muted) }
        else if (action === "up" || action === "down") {
            level = BarScroll.volume(level, action === "up" ? steps : -steps)
            audio.setVolume(level)
            // Raising the volume is a request to hear something: unmute, the
            // way every other desktop's volume-up key does.
            if (action === "up" && muted) { muted = false; audio.setOutputMuted(false) }
        } else return
        show("volume", muted ? "Muted" : "Volume · " + Math.round(level * 100) + "%",
             muted ? "󰝟" : "󰕾", muted ? 0 : level)
    }
    function micMute() {
        const mic = audio.microphone
        if (!mic.available) return
        const muted = !mic.muted
        mic.setInputMuted(muted)
        show("volume", muted ? "Microphone muted" : "Microphone on", muted ? "󰍭" : "󰍬", muted ? 0 : mic.volume)
    }
}
