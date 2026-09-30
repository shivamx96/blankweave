import QtQuick
import QtQuick.Layouts
import "../Components"

WidgetFrame {
    id: root

    readonly property var usage: root.bar.shell.agentUsage
    readonly property bool available: usage.available

    visible: available
    icon: "󰚩"
    iconOnly: true
    active: usagePanel.open
    attention: usage.low
    tooltip: {
        const lines = ["Coding agent usage"]
        for (const agent of root.usage.agents) {
            if (!agent.authenticated)
                continue
            const remaining = (agent.windows || []).filter(window => !root.usage.expired(window))
                .map(window => window.label + ": " + Math.floor(window.remaining) + "% left")
            lines.push(agent.name + " · " + (remaining.length ? remaining.join(" / ") : "Usage unavailable")
                + (root.usage.stale(agent) && remaining.length ? " (stale)" : ""))
        }
        return lines.join("\n")
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            usagePanel.open = !usagePanel.open
        }
    }

    ControlPopup {
        id: usagePanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 380
        onOpenChanged: {
            if (open)
                root.usage.refresh(false)
        }

        ControlPanelHeader {
            theme: root.theme
            icon: root.icon
            title: "AGENT USAGE"
            subtitle: root.usage.busy ? "Refreshing…" : "Subscription allowance remaining"
            actions: [{ "id": "refresh", "icon": "󰑐" }]
            onActionPressed: root.usage.refresh(true)
        }

        ControlDivider { theme: root.theme }

        Text {
            visible: root.usage.error !== ""
            Layout.fillWidth: true
            text: root.usage.error
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.theme.warning
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
        }

        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(providerList.implicitHeight, Math.max(150, root.bar.screen.height - 220), 500)
            contentHeight: providerList.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: providerList
                width: scroll.width
                spacing: 18

                Repeater {
                    model: root.usage.agents

                    delegate: ColumnLayout {
                        id: provider
                        required property var modelData
                        readonly property bool stale: root.usage.stale(modelData)
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: provider.modelData.name
                                color: root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.textSize
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: root.usage.planLabel(provider.modelData)
                                textFormat: Text.PlainText
                                color: root.theme.textMuted
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.microTextSize
                            }
                        }

                        Repeater {
                            model: provider.modelData.windows || []

                            delegate: ColumnLayout {
                                id: allowance
                                required property var modelData
                                readonly property bool expired: root.usage.expired(modelData)
                                readonly property bool uncertain: provider.stale || expired
                                Layout.fillWidth: true
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: allowance.modelData.label
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: root.theme.textMuted
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.smallTextSize
                                    }
                                    Text {
                                        text: allowance.expired ? "Awaiting update"
                                            : Math.floor(allowance.modelData.remaining) + "% left" + (provider.stale ? " · stale" : "")
                                        color: allowance.uncertain ? root.theme.textMuted
                                            : allowance.modelData.remaining <= 20 ? root.theme.warning : root.theme.text
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.smallTextSize
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 5
                                    radius: 2.5
                                    color: root.theme.surfaceRaised

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(100, allowance.modelData.remaining)) / 100
                                        height: parent.height
                                        radius: parent.radius
                                        visible: !allowance.expired
                                        opacity: provider.stale ? 0.35 : 1
                                        color: allowance.modelData.remaining <= 20 ? root.theme.warning : root.theme.accentBright
                                    }
                                }

                                Text {
                                    text: root.usage.resetText(allowance.modelData)
                                    color: root.theme.textMuted
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.microTextSize
                                }
                            }
                        }

                        Text {
                            visible: Boolean(provider.modelData.message)
                            Layout.fillWidth: true
                            text: provider.modelData.message || ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.smallTextSize
                        }

                        Text {
                            visible: Boolean(provider.modelData.updatedAt)
                            text: root.usage.age(provider.modelData)
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.microTextSize
                        }

                    }
                }
            }
        }
    }
}
