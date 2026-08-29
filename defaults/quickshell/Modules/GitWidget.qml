import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"

    property var repos: ({
        "available": false,
        "root": "",
        "ideAvailable": false,
        "error": "",
        "skipped": 0,
        "total": 0,
        "dirty": 0,
        "ahead": 0,
        "repos": []
    })
    property var prs: ({
        "available": false,
        "authenticated": false,
        "stale": false,
        "error": "",
        "login": "",
        "authored": [],
        "review": [],
        "authoredCount": 0,
        "reviewCount": 0,
        "draftCount": 0
    })
    property string activeTab: "repos"

    readonly property var repoRows: repos.repos || []
    readonly property int repoCount: Number(repos.total || 0)
    readonly property int dirtyCount: Number(repos.dirty || 0)
    readonly property int reviewCount: Number(prs.reviewCount || 0)
    readonly property int authoredCount: Number(prs.authoredCount || 0)
    readonly property bool signedIn: Boolean(prs.authenticated)
    readonly property bool ideAvailable: Boolean(repos.ideAvailable)
    // Pull requests are useful on their own, so the widget also earns its place
    // on a machine that has no local checkouts yet.
    readonly property bool available: repoCount > 0 || signedIn

    function prCommand(maxAge) {
        return root.shellDir + "/git-prs.sh --max-age " + maxAge
    }

    function updateRepos(payload) {
        try {
            root.repos = JSON.parse(payload)
        } catch (error) {
            root.repos = {
                "available": false,
                "ideAvailable": false,
                "error": "Could not read project directory",
                "total": 0,
                "dirty": 0,
                "skipped": 0,
                "repos": []
            }
        }
    }

    function updatePrs(payload) {
        try {
            root.prs = JSON.parse(payload)
        } catch (error) {
            root.prs = {
                "available": false,
                "authenticated": false,
                "error": "Could not read GitHub response",
                "authored": [],
                "review": [],
                "authoredCount": 0,
                "reviewCount": 0
            }
        }
    }

    // Pull requests are searched account-wide, so only some of them map back to
    // a checkout under the scanned project directory.
    function localPathFor(nameWithOwner) {
        const key = String(nameWithOwner || "").toLowerCase()
        if (!key)
            return ""
        const rows = root.repoRows
        for (let index = 0; index < rows.length; index++) {
            if (String(rows[index].nameWithOwner || "").toLowerCase() === key)
                return String(rows[index].path || "")
        }
        return ""
    }

    function repoSubtitle(repo) {
        const parts = [String(repo.branch || "unknown")]
        if (Number(repo.ahead || 0) > 0)
            parts.push(Number(repo.ahead) + " ahead")
        if (Number(repo.behind || 0) > 0)
            parts.push(Number(repo.behind) + " behind")
        if (parts.length === 1 && repo.lastCommit)
            parts.push(String(repo.lastCommit))
        return parts.join("  ·  ")
    }

    function projectAction() {
        return root.ideAvailable
            ? { "id": "project", "icon": "󰲋", "label": "IDE" }
            : { "id": "project", "icon": "󰉋", "label": "FILES" }
    }

    function openProject(path) {
        if (!path)
            return
        gitPanel.open = false
        root.bar.run(root.ideAvailable ? ["idea", path] : ["xdg-open", path])
    }

    function openInBrowser(url) {
        if (!url)
            return
        gitPanel.open = false
        root.bar.run(["xdg-open", url])
    }

    visible: available
    icon: "󰊢"
    iconOnly: root.reviewCount === 0
    label: root.reviewCount > 0 ? String(root.reviewCount) : ""
    active: root.reviewCount > 0 || gitPanel.open
    tooltip: {
        const lines = []
        if (root.reviewCount > 0)
            lines.push(root.reviewCount + " pull request" + (root.reviewCount === 1 ? "" : "s") + " awaiting your review")
        if (root.authoredCount > 0)
            lines.push(root.authoredCount + " open pull request" + (root.authoredCount === 1 ? "" : "s") + " of yours")
        lines.push(root.repoCount + " project" + (root.repoCount === 1 ? "" : "s")
            + (root.dirtyCount > 0 ? " · " + root.dirtyCount + " with changes" : ""))
        lines.push("Click for projects and pull requests")
        return lines.join("\n")
    }

    ScriptPoller {
        id: reposPoller
        command: root.shellDir + "/git-repos.sh"
        // Local scanning only runs while the panel is open; the startup pass is
        // enough to decide whether the widget belongs on the bar at all.
        interval: gitPanel.open ? 6000 : 0
        onUpdated: payload => root.updateRepos(payload)
    }

    ScriptPoller {
        id: prPoller
        command: root.prCommand(300)
        // Keeps the review badge live without spending a search request per tick.
        interval: gitPanel.open ? 120000 : 600000
        onUpdated: payload => {
            root.updatePrs(payload)
            prPoller.command = root.prCommand(gitPanel.open ? 45 : 300)
        }
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            gitPanel.open = !gitPanel.open
        }
    }

    ControlPopup {
        id: gitPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 460

        onOpenChanged: {
            if (!open)
                return
            reposPoller.refresh()
            prPoller.command = root.prCommand(45)
            prPoller.refresh()
        }

        ControlPanelHeader {
            theme: root.theme
            icon: "󰊢"
            title: "GIT"
            subtitle: root.signedIn
                ? "@" + String(root.prs.login || "github")
                    + (root.prs.stale ? "  ·  showing cached results" : "")
                : "Not signed in to GitHub"
            actions: [{ "id": "refresh", "icon": "󰑐" }]
            onActionPressed: actionId => {
                if (actionId !== "refresh")
                    return
                reposPoller.refresh()
                prPoller.command = root.prCommand(0)
                prPoller.refresh()
            }
        }

        ControlDivider { theme: root.theme }

        ControlTabs {
            theme: root.theme
            currentId: root.activeTab
            tabs: [
                { "id": "repos", "label": "PROJECTS", "badge": 0 },
                { "id": "prs", "label": "PULL REQUESTS", "badge": root.reviewCount }
            ]
            onSelected: tabId => root.activeTab = tabId
        }

        // ---- Projects -------------------------------------------------------

        ColumnLayout {
            visible: root.activeTab === "repos"
            Layout.fillWidth: true
            spacing: 10

            ApplicationSummary {
                theme: root.theme
                metrics: [
                    { "label": "PROJECTS", "value": root.repoCount, "active": root.repoCount > 0 },
                    { "label": "CHANGED", "value": root.dirtyCount, "attention": root.dirtyCount > 0 },
                    { "label": "UNPUSHED", "value": Number(root.repos.ahead || 0) }
                ]
            }

            ControlSectionLabel {
                theme: root.theme
                text: "IDEAPROJECTS"
            }

            ListView {
                id: repoList
                visible: root.repoRows.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Math.min(contentHeight, 320) : 0
                model: root.repoRows
                clip: true
                spacing: 2
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                delegate: ApplicationListRow {
                    id: repoRow

                    required property var modelData
                    readonly property int changed: Number(modelData.dirty || 0)

                    width: repoList.width
                    rowHeight: 48
                    theme: root.theme
                    icon: "󰘬"
                    title: String(modelData.name || "Repository")
                    subtitle: root.repoSubtitle(modelData)
                    subtitleKind: Number(modelData.behind || 0) > 0 ? "warning" : "neutral"
                    status: changed > 0
                        ? changed + (changed === 1 ? " change" : " changes")
                        : "Clean"
                    statusKind: changed > 0 ? "warning" : "success"
                    active: changed > 0 || Number(modelData.ahead || 0) > 0
                    actions: {
                        const result = [root.projectAction()]
                        if (String(modelData.webUrl || ""))
                            result.push({ "id": "github", "icon": "󰊤" })
                        return result
                    }
                    onActionPressed: actionId => {
                        if (actionId === "project")
                            root.openProject(String(repoRow.modelData.path || ""))
                        else if (actionId === "github")
                            root.openInBrowser(String(repoRow.modelData.webUrl || ""))
                    }
                }
            }

            ApplicationEmptyState {
                visible: root.repoRows.length === 0
                theme: root.theme
                icon: "󰘬"
                title: root.repos.error ? "Projects unavailable" : "No tracked projects"
                message: root.repos.error
                    ? String(root.repos.error)
                    : (Number(root.repos.skipped || 0) > 0
                        ? Number(root.repos.skipped) + " folder"
                            + (Number(root.repos.skipped) === 1 ? " has" : "s have")
                            + " no origin remote configured."
                        : "Clone a repository into ~/IdeaProjects to see it here.")
            }
        }

        // ---- Pull requests --------------------------------------------------

        ColumnLayout {
            visible: root.activeTab === "prs"
            Layout.fillWidth: true
            spacing: 10

            ApplicationSummary {
                visible: root.signedIn
                theme: root.theme
                metrics: [
                    { "label": "TO REVIEW", "value": root.reviewCount, "active": root.reviewCount > 0 },
                    { "label": "YOURS", "value": root.authoredCount },
                    { "label": "DRAFTS", "value": Number(root.prs.draftCount || 0) }
                ]
            }

            ControlSectionLabel {
                visible: root.signedIn && root.reviewCount > 0
                theme: root.theme
                text: "AWAITING YOUR REVIEW"
            }

            ListView {
                id: reviewList
                visible: root.signedIn && root.reviewCount > 0
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Math.min(contentHeight, 190) : 0
                model: root.prs.review || []
                clip: true
                spacing: 2
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                delegate: ApplicationListRow {
                    id: reviewRow

                    required property var modelData
                    readonly property string localPath: root.localPathFor(modelData.repo)

                    width: reviewList.width
                    rowHeight: 48
                    theme: root.theme
                    icon: "󰘭"
                    title: "#" + Number(modelData.number || 0) + "  " + String(modelData.title || "")
                    subtitle: String(modelData.repo || "")
                        + (modelData.author ? "  ·  @" + String(modelData.author) : "")
                        + (modelData.updated ? "  ·  " + String(modelData.updated) : "")
                    status: "Review"
                    statusKind: "warning"
                    active: true
                    actions: {
                        const result = []
                        if (reviewRow.localPath)
                            result.push(root.projectAction())
                        result.push({ "id": "open", "icon": "󰏌", "label": "OPEN" })
                        return result
                    }
                    onActionPressed: actionId => {
                        if (actionId === "project")
                            root.openProject(reviewRow.localPath)
                        else if (actionId === "open")
                            root.openInBrowser(String(reviewRow.modelData.url || ""))
                    }
                }
            }

            ControlSectionLabel {
                visible: root.signedIn && root.authoredCount > 0
                theme: root.theme
                text: "OPENED BY YOU"
            }

            ListView {
                id: authoredList
                visible: root.signedIn && root.authoredCount > 0
                Layout.fillWidth: true
                Layout.preferredHeight: visible
                    ? Math.min(contentHeight, root.reviewCount > 0 ? 190 : 330)
                    : 0
                model: root.prs.authored || []
                clip: true
                spacing: 2
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                delegate: ApplicationListRow {
                    id: authoredRow

                    required property var modelData
                    readonly property string localPath: root.localPathFor(modelData.repo)

                    width: authoredList.width
                    rowHeight: 48
                    theme: root.theme
                    icon: "󰘭"
                    title: "#" + Number(modelData.number || 0) + "  " + String(modelData.title || "")
                    subtitle: String(modelData.repo || "")
                        + (modelData.updated ? "  ·  " + String(modelData.updated) : "")
                    status: modelData.isDraft ? "Draft" : ""
                    statusKind: "neutral"
                    active: !modelData.isDraft
                    actions: {
                        const result = []
                        if (authoredRow.localPath)
                            result.push(root.projectAction())
                        result.push({ "id": "open", "icon": "󰏌", "label": "OPEN" })
                        return result
                    }
                    onActionPressed: actionId => {
                        if (actionId === "project")
                            root.openProject(authoredRow.localPath)
                        else if (actionId === "open")
                            root.openInBrowser(String(authoredRow.modelData.url || ""))
                    }
                }
            }

            ApplicationEmptyState {
                visible: !root.signedIn || (root.reviewCount === 0 && root.authoredCount === 0)
                theme: root.theme
                icon: "󰘭"
                title: root.signedIn ? "No open pull requests" : "GitHub sign-in required"
                message: root.signedIn
                    ? (String(root.prs.error) || "Pull requests you opened or are asked to review appear here.")
                    : (String(root.prs.error) || "Sign in with the GitHub CLI to list your pull requests.")
            }

            ControlAction {
                visible: !root.signedIn
                theme: root.theme
                icon: "󰍂"
                label: "SIGN IN WITH GITHUB"
                onPressed: {
                    gitPanel.open = false
                    root.bar.run(["ghostty", "-e", "gh", "auth", "login"])
                }
            }
        }
    }
}
