.pragma library

function suspendCommand() { return ["systemctl", "suspend"] }

function lockCommand() { return ["sh", "-c", "~/.local/share/blankweave/shell/lock.sh"] }
function restartCommand() { return ["systemctl", "reboot"] }
function shutdownCommand() { return ["systemctl", "poweroff"] }
function exitCommand() { return ["uwsm", "stop"] }
function exitLabel(automatic) { return automatic ? "Restart session" : "Log out" }
function themeCommand(shellDir) { return [shellDir + "/theme-apply.sh", "toggle"] }
function dndCommand(shellDir) { return ["python3", shellDir + "/notification-settings.py", "toggle"] }
