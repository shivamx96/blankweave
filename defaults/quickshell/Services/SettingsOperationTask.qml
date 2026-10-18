import QtQuick

SettingsTask {
    id: root
    readonly property SettingsOperationDraft draft: SettingsOperationDraft { backend: root }
}
