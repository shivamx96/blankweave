import QtQuick
import Quickshell
import "Components"

ShellRoot {
    Theme { id: theme }
    ControlSlider { id: slider; theme: theme }
    function check(ok, message) { if (!ok) throw new Error(message) }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            try {
                theme.designDefaults = ({})
                theme.resolved = ({colors: {}, design: {}})
                check(theme.spacing("panel") === 18, "Missing defaults must retain spacing")
                check(theme.panelRadius === 14, "Legacy radius changed")
                theme.resolved = ({design: {
                    spacing: {panel: 24, barItemGap: 0},
                    shape: {panelRadius: 8, borderWidth: 0},
                    typography: {textSize: 16, fontFamily: "Test Sans"},
                    motion: {duration: 240, easing: "inOutCubic"},
                    materials: {gradientEnabled: true, gradientStart: "#12345680", gradientEnd: "#654321ff"}
                }})
                theme.textScale = 1.3
                check(theme.spacing("panel") === 24 && theme.spacing("barItemGap") === 0, "Override lost")
                check(theme.panelRadius === 8 && theme.borderWidth === 0, "Shape overrides lost")
                check(theme.textSize === 21 && theme.fontFamily === "Test Sans", "Typography must respect user scaling")
                check(theme.motionDuration === 240 && theme.motionEasing === Easing.InOutCubic, "Motion override lost")
                check(theme.gradientEnabled, "Gradient should be enabled")
                check(Math.abs(theme.gradientStart.a - 128 / 255) < 0.01, "CSS alpha was not converted")
                theme.reducedMotion = true
                theme.highContrast = true
                check(theme.motionDuration === 0, "Reduced motion must override theme")
                check(!theme.gradientEnabled && theme.borderWidth >= 1, "Contrast must override decoration")
                check(String(slider.trackColor) === "#767676", "High contrast slider track must differ from text")
                check(String(slider.fillColor) === "#8ac7ff", "Dark contrast fill must retain accent")
                theme.resolved = ({mode: "light", design: {}})
                check(String(slider.trackColor) === "#767676", "Light high contrast slider track must differ from text")
                check(String(slider.fillColor) === "#003a80", "Light contrast fill must retain accent")
                theme.highContrast = false
                theme.resolved = ({colors: {outlineStrong: "#69517f", accent: "#ac88d4"}, design: {}})
                check(String(slider.trackColor) === "#69517f", "Normal slider must use theme track")
                check(String(slider.fillColor) === "#ac88d4", "Normal fill must retain accent")
                theme.resolved = ({design: {}})
                check(theme.panelRadius === 14 && theme.spacing("panel") === 18, "Theme switch retained previous overrides")
                console.log("THEME_RUNTIME_PASSED")
                Qt.quit()
            } catch (error) { console.error(error); Qt.exit(1) }
        }
    }
}
