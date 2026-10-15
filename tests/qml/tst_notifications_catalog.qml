import QtQuick
import QtTest
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog
TestCase {
    name: "NotificationsCatalog"
    function test_notifications_are_live_and_temporary_awake_is_removed() {
        let rows = []
        for (const page of Catalog.pages)
            for (const group of page.groups) rows = rows.concat(group.rows)
        for (const id of ["dnd", "notifications"]) {
            const row = rows.find(r => r.id === id)
            verify(row.live); compare(row.kind, "notifications")
        }
        verify(!rows.some(r => r.id === "awake"))
    }
}
