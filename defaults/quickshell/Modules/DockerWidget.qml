import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/blankweave/shell"
    readonly property string dockerMark: "docker"
    property var status: ({
        "available": false,
        "daemonRunning": false,
        "error": "",
        "name": "Docker Engine",
        "version": "",
        "storageDriver": "",
        "totalContainers": 0,
        "runningContainers": 0,
        "stoppedContainers": 0,
        "images": 0,
        "containers": []
    })
    property var expandedStacks: ({})
    property int expansionRevision: 0
    readonly property bool running: Boolean(status.daemonRunning)

    function updateStatus(payload) {
        if (!payload)
            return
        try {
            root.status = JSON.parse(payload)
        } catch (error) {
            root.status = {
                "available": true,
                "daemonRunning": true,
                "error": "Could not read Docker status",
                "containers": []
            }
        }
        root.syncStackModel()
    }

    function groupedContainers() {
        const containers = root.status.containers || []
        const groups = ({})
        for (let index = 0; index < containers.length; index++) {
            const container = containers[index]
            const project = String(container.project || "")
            const stackId = project ? "compose:" + project : "standalone"
            if (!groups[stackId]) {
                groups[stackId] = {
                    "stackId": stackId,
                    "title": project || "Standalone containers",
                    "kind": project ? "compose" : "standalone",
                    "containers": []
                }
            }
            groups[stackId].containers.push(container)
        }

        const result = Object.keys(groups).map(key => groups[key])
        result.sort((left, right) => {
            if (left.kind !== right.kind)
                return left.kind === "compose" ? -1 : 1
            return left.title.localeCompare(right.title)
        })
        return result
    }

    function syncStackModel() {
        const desired = root.groupedContainers()
        const identifiers = ({})
        for (let index = 0; index < desired.length; index++)
            identifiers[desired[index].stackId] = true

        for (let index = stackModel.count - 1; index >= 0; index--) {
            if (!identifiers[String(stackModel.get(index).stackId || "")])
                stackModel.remove(index)
        }

        for (let index = 0; index < desired.length; index++) {
            const group = desired[index]
            const entry = {
                "stackId": group.stackId,
                "title": group.title,
                "kind": group.kind,
                "containerCount": group.containers.length,
                "containersJson": JSON.stringify(group.containers)
            }
            let currentIndex = -1
            for (let candidate = index; candidate < stackModel.count; candidate++) {
                if (stackModel.get(candidate).stackId === entry.stackId) {
                    currentIndex = candidate
                    break
                }
            }
            if (currentIndex < 0) {
                stackModel.insert(index, entry)
            } else {
                if (currentIndex !== index)
                    stackModel.move(currentIndex, index, 1)
                stackModel.set(index, entry)
            }
        }
    }

    function stackExpanded(stackId, index) {
        root.expansionRevision
        if (Object.prototype.hasOwnProperty.call(root.expandedStacks, stackId))
            return Boolean(root.expandedStacks[stackId])
        return index === 0
    }

    function toggleStack(stackId, index) {
        const next = ({})
        for (const key in root.expandedStacks)
            next[key] = root.expandedStacks[key]
        next[stackId] = !root.stackExpanded(stackId, index)
        root.expandedStacks = next
        root.expansionRevision += 1
    }

    function containerSubtitle(container) {
        const image = String(container.image || "")
        const ports = String(container.portsText || "")
        return ports ? image + " · " + ports : image
    }

    visible: running
    iconMark: root.dockerMark
    iconOnly: true
    active: dockerPanel.open
    tooltip: Number(status.runningContainers || 0) > 0
        ? "Docker · " + Number(status.runningContainers || 0) + " containers running\nClick for workloads"
        : "Docker Engine running · No active containers\nClick for workloads"

    ScriptPoller {
        id: statusPoller
        command: root.shellDir + "/docker-status.sh"
        interval: dockerPanel.open ? 4000 : 12000
        onUpdated: payload => root.updateStatus(payload)
    }

    ListModel {
        id: stackModel
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            dockerPanel.open = !dockerPanel.open
        }
    }

    ControlPopup {
        id: dockerPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 430

        onOpenChanged: {
            if (open)
                statusPoller.refresh()
        }

        ControlPanelHeader {
            theme: root.theme
            iconMark: root.dockerMark
            title: "DOCKER"
            subtitle: String(root.status.name || "Docker Engine")
                + (root.status.version ? " · " + String(root.status.version) : "")
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "RUNNING",
                    "value": Number(root.status.runningContainers || 0),
                    "active": Number(root.status.runningContainers || 0) > 0
                },
                {
                    "label": "STOPPED",
                    "value": Number(root.status.stoppedContainers || 0)
                },
                {
                    "label": "IMAGES",
                    "value": Number(root.status.images || 0)
                }
            ]
        }

        ControlSectionLabel {
            theme: root.theme
            text: "RUNNING WORKLOADS"
        }

        ListView {
            id: stackList
            visible: stackModel.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(contentHeight, 430) : 0
            model: stackModel
            clip: true
            spacing: 2
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: stackDelegate

                required property int index
                required property string stackId
                required property string title
                required property string kind
                required property int containerCount
                required property string containersJson
                readonly property bool expanded: root.stackExpanded(stackId, index)
                readonly property var containerRows: {
                    try {
                        return JSON.parse(containersJson)
                    } catch (error) {
                        return []
                    }
                }

                width: stackList.width
                height: 44 + (expanded ? containerRows.length * 48 : 0)

                ApplicationAccordionHeader {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    theme: root.theme
                    icon: stackDelegate.kind === "compose" ? "󰡨" : "󰆍"
                    title: stackDelegate.title
                    subtitle: stackDelegate.kind === "compose" ? "Compose project" : "Not managed by Compose"
                    badge: stackDelegate.containerCount + " running"
                    expanded: stackDelegate.expanded
                    active: true
                    onPressed: root.toggleStack(stackDelegate.stackId, stackDelegate.index)
                }

                Column {
                    visible: stackDelegate.expanded
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 44

                    Repeater {
                        model: stackDelegate.containerRows

                        delegate: ApplicationListRow {
                            id: containerRow

                            required property var modelData
                            property string copiedValue: ""

                            width: stackDelegate.width
                            height: implicitHeight
                            rowHeight: 48
                            theme: root.theme
                            icon: "󰡨"
                            title: String(modelData.service || modelData.name || "Container")
                                + (modelData.service && modelData.name
                                    ? "  ·  " + String(modelData.name)
                                    : "")
                            subtitle: root.containerSubtitle(modelData)
                            subtitleKind: modelData.health === "unhealthy" ? "critical" : "neutral"
                            status: modelData.health
                                ? String(modelData.health)
                                : "Running"
                            statusKind: modelData.health === "unhealthy" ? "critical" : "success"
                            active: true
                            actions: {
                                const result = []
                                if (String(modelData.copyPorts || "")) {
                                    result.push({
                                        "id": "copy-port",
                                        "icon": containerRow.copiedValue === "port" ? "󰄬" : "󰆏",
                                        "label": "COPY",
                                        "active": containerRow.copiedValue === "port"
                                    })
                                }
                                result.push({ "id": "logs", "icon": "󰆍", "label": "LOG" })
                                return result
                            }
                            onActionPressed: actionId => {
                                if (actionId === "copy-port" && modelData.copyPorts) {
                                    Quickshell.clipboardText = String(modelData.copyPorts)
                                    containerRow.copiedValue = "port"
                                    copiedTimer.restart()
                                } else if (actionId === "logs" && modelData.id) {
                                    dockerPanel.open = false
                                    root.bar.run([
                                        "ghostty",
                                        "-e",
                                        "docker",
                                        "logs",
                                        "--follow",
                                        "--tail",
                                        "200",
                                        String(modelData.id)
                                    ])
                                }
                            }

                            Timer {
                                id: copiedTimer
                                interval: 1400
                                onTriggered: containerRow.copiedValue = ""
                            }
                        }
                    }
                }
            }
        }

        ApplicationEmptyState {
            visible: stackModel.count === 0
            theme: root.theme
            icon: "󰡨"
            title: root.status.error ? "Docker unavailable" : "No running containers"
            message: root.status.error
                ? String(root.status.error)
                : "Compose projects and standalone containers will appear here when active."
        }
    }

    Component.onCompleted: root.syncStackModel()
}
