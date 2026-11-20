.pragma library
function panel(item) {
    for (let p = item; p; p = p.parent) if (p.panelController) return p.panelController
    return null
}
function controls(scope) {
    const result = []
    function visit(item) {
        if (!item.visible || !item.enabled) return
        if (item.activeFocusOnTab) { result.push(item); return }
        for (const child of item.children || []) visit(child)
    }
    visit(scope)
    return result.sort((a, b) => {
        const x = a.mapToItem(scope, 0, 0), y = b.mapToItem(scope, 0, 0)
        return Math.abs(x.y - y.y) > 8 ? x.y - y.y : x.x - y.x
    })
}
function key(scope, event) {
    const items = controls(scope), index = items.findIndex(i => i.activeFocus)
    if (index >= 0 && items[index].panelTextInput && ![Qt.Key_Tab, Qt.Key_Backtab].includes(event.key)) return false
    let next = index
    if (index >= 0 && [Qt.Key_Down, Qt.Key_Up].includes(event.key)) {
        const currentY = items[index].mapToItem(scope, 0, items[index].height / 2).y
        const direction = event.key === Qt.Key_Down ? 1 : -1
        const rows = items.map((item, i) => ({index: i, y: item.mapToItem(scope, 0, item.height / 2).y}))
            .filter(row => direction * (row.y - currentY) > 8)
            .sort((a, b) => direction * (a.y - b.y) || a.index - b.index)
        next = rows.length ? rows[0].index : (direction > 0 ? 0 : items.length - 1)
    }
    else if ([Qt.Key_Tab, Qt.Key_Down, Qt.Key_Right].includes(event.key)) next = (index + (event.modifiers & Qt.ShiftModifier ? -1 : 1) + items.length) % items.length
    else if ([Qt.Key_Backtab, Qt.Key_Up, Qt.Key_Left].includes(event.key)) next = (index - 1 + items.length) % items.length
    else if (event.key === Qt.Key_Home) next = 0
    else if (event.key === Qt.Key_End) next = items.length - 1
    else return false
    if (items[next]) {
        const owner = panel(items[next])
        if (owner) owner.focusIdentity = items[next].focusIdentity || ""
        items[next].forceActiveFocus(Qt.TabFocusReason)
        reveal(items[next])
    }
    event.accepted = true
    return true
}

function route(item, event) {
    const owner = panel(item)
    if (!owner) return false
    owner.keyboardMode = true
    if (item.panelTextInput && ![Qt.Key_Tab, Qt.Key_Backtab].includes(event.key)) return false
    if ([Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End].includes(event.key)) return key(owner.navigationScope, event)
    return false
}

function reveal(item) {
    for (let p = item.parent; p; p = p.parent) {
        if (p.contentItem && p.contentHeight !== undefined && p.contentY !== undefined) {
            const point = item.mapToItem(p.contentItem, 0, 0)
            if (point.y < p.contentY) p.contentY = Math.max(0, point.y)
            else if (point.y + item.height > p.contentY + p.height) p.contentY = Math.max(0, Math.min(p.contentHeight - p.height, point.y + item.height - p.height))
        }
    }
}
