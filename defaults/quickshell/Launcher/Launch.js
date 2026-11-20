// DesktopEntry.command is Quickshell's parsed argv, with Exec field codes resolved.
function activate(entry, detached) {
    if (!entry.runInTerminal) {
        entry.execute()
        return
    }
    const command = ["ghostty"]
    if (entry.workingDirectory)
        command.push("--working-directory=" + entry.workingDirectory)
    command.push("-e")
    for (const argument of entry.command)
        command.push(argument)
    detached(command)
}
