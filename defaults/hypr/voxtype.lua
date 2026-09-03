-- Blankweave local voice dictation. This file is loaded only when the
-- voice-dictation installer profile is enabled.

-- Quick toggle for longer dictation.
hl.bind("SUPER + D", hl.dsp.exec_cmd("voxtype record toggle"), {
    description = "Toggle voice dictation",
})

-- Push-to-talk: ordinary F-keys have reliable press/release events under
-- Hyprland. The laptop's Fn layer may expose this physical key as F12.
hl.bind("F12", hl.dsp.exec_cmd("voxtype record start"), {
    description = "Hold to dictate",
})
hl.bind("F12", hl.dsp.exec_cmd("voxtype record stop"), {
    release = true,
    description = "Release to transcribe",
})
