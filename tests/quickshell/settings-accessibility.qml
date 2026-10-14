import QtQuick
import QtQuick.Layouts
import Quickshell
import "Services"
import "Settings"
import "Components"
import "."
ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("accessibility.py").toString().replace("file://", "")
    Theme { id: theme; resolved: ({theme: "custom", mode: "dark", colors: Object.assign({}, contrastDark, {text: "#dddddd"})}) }
    SettingsAccessibility { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 700
        ColumnLayout {
            width: 580
            SettingsAccessibilityControls { id: contrast; theme: theme; backend: backend; settingId: "contrast"; Layout.fillWidth: true }
            SettingsAccessibilityControls { id: motion; theme: theme; backend: backend; settingId: "motion"; Layout.fillWidth: true }
            ControlAction { id: action; theme: theme; label: "Motion probe"; width: 200; height: 30 }
        }
    }
    function check(condition, message) { if (!condition) throw new Error("Step " + step + ": " + message) }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    function luminance(hex) {
        const channels = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(c => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
    function checkPalette(palette) {
        for (const foreground of ["text", "textMuted", "accent", "accentBright", "success", "warning", "critical"])
            for (const background of ["canvas", "surface", "surfaceRaised", "surfaceHover", "surfacePressed", "accentSurface"]) {
                const a = luminance(palette[foreground]), b = luminance(palette[background])
                check((Math.max(a,b) + 0.05) / (Math.min(a,b) + 0.05) >= 4.5, "Low palette contrast: " + foreground + "/" + background)
            }
    }
    Timer {
        interval: 180; running: true; repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(!backend.active && !theme.highContrast && !theme.reducedMotion, "Initial state")
                    test.checkPalette(theme.contrastDark); test.checkPalette(theme.contrastLight)
                    backend.active = true
                    break
                case 1:
                    test.check(backend.writable, "Controls unavailable")
                    test.find(contrast, "accessibility_high_contrast").activated(1)
                    test.check(backend.busy && !backend.saved.high_contrast, "Optimistic value")
                    backend.active = false
                    break
                case 2:
                    test.check(theme.highContrast && String(theme.text) === "#ffffff" && theme.themeId === "custom", "Contrast did not preserve theme")
                    theme.resolved = Object.assign({}, theme.resolved, {mode: "light"})
                    test.check(String(theme.text) === "#000000", "Light contrast palette missing")
                    test.find(motion, "accessibility_reduced_motion").activated(1)
                    break
                case 3:
                    test.check(theme.reducedMotion && backend.saved.reduced_motion, "Motion preference not loaded")
                    action.active = true
                    Qt.callLater(() => {
                        const line = action.children.find(c => c.height === 1)
                        test.check(line && line.width === Math.min(action.width - 12, 140), "Control transition did not finish immediately")
                    })
                    test.find(motion, "accessibility_reduced_motion").activated(0)
                    break
                case 4:
                    test.check(backend.error.includes("overrides") && theme.reducedMotion, "Rejected write accepted")
                    test.find(contrast, "accessibility_high_contrast").activated(0)
                    break
                case 5:
                    test.check(!theme.highContrast && String(theme.text) === "#dddddd" && theme.themeId === "custom", "Original palette not restored")
                    backend.helper = "/nonexistent/accessibility.py"; backend.refresh(true)
                    break
                case 6:
                    test.check(!backend.ready && !backend.writable, "Read failure permits writes")
                    backend.helper = test.fixture; backend.refresh(true)
                    break
                case 7:
                    test.check(backend.ready && !backend.error, "Retry failed")
                    console.log("SETTINGS_ACCESSIBILITY_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
