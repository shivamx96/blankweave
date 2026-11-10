pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Controls

// Own every painted surface: the desktop Qt style can retain a light palette
// even when Blankweave switches themes while this window is open.
Controls.ComboBox {
    id: root
    required property var theme

    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)
    implicitWidth: 190
    leftPadding: root.theme.spacing("xl")
    rightPadding: root.theme.spacing("content")
    hoverEnabled: true
    font.family: theme.fontFamily
    font.weight: theme.textWeight
    font.pixelSize: theme.smallTextSize

    contentItem: Text {
        text: root.displayText
        textFormat: Text.PlainText
        font: root.font
        color: root.enabled ? root.theme.text : root.theme.textMuted
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: root.width - width - 12
        y: (root.height - height) / 2
        text: "▾"
        font: root.font
        color: root.enabled ? root.theme.text : root.theme.textMuted
    }

    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.down ? root.theme.surfacePressed
            : root.hovered && root.enabled ? root.theme.surfaceHover : root.theme.surfaceRaised
        border.width: root.activeFocus ? Math.max(1, root.theme.borderWidth) : root.theme.borderWidth
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }

    delegate: Controls.ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: menu.width
        implicitHeight: Math.max(38, implicitContentHeight + topPadding + bottomPadding)
        leftPadding: root.theme.spacing("xl")
        rightPadding: root.theme.spacing("xl")
        text: root.textAt(index)
        highlighted: root.highlightedIndex === index
        hoverEnabled: true
        font: root.font
        Accessible.name: text

        contentItem: Text {
            text: option.text
            textFormat: Text.PlainText
            font: option.font
            color: option.highlighted || option.index === root.currentIndex
                ? root.theme.accentBright : root.theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: root.theme.widgetRadius
            color: option.down ? root.theme.surfacePressed
                : option.highlighted ? root.theme.accentSurface
                : option.hovered ? root.theme.surfaceHover : "transparent"
            border.width: option.visualFocus ? Math.max(1, root.theme.borderWidth) : 0
            border.color: root.theme.accentBright
        }
    }

    popup: Controls.Popup {
        y: root.height + 4
        width: root.width
        padding: root.theme.spacing("xs")
        topMargin: root.theme.spacing("md")
        bottomMargin: root.theme.spacing("md")
        height: Math.min(menu.contentHeight + padding * 2, 320)
        popupType: Controls.Popup.Item

        contentItem: ListView {
            id: menu
            clip: true
            model: root.delegateModel
            currentIndex: root.highlightedIndex
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {
                visible: menu.contentHeight > menu.height
                contentItem: Rectangle {
                    implicitWidth: 3
                    implicitHeight: 20
                    radius: 1
                    color: root.theme.textMuted
                }
            }
        }
        background: Rectangle {
            radius: root.theme.widgetRadius
            color: root.theme.panelSurface
            border.width: root.theme.borderWidth
            border.color: root.theme.outline
        }
    }
}
