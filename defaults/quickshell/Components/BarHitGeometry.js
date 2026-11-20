.pragma library

// Traverse layout wrappers, stopping at each painted entry. Loaders also mark
// non-WidgetFrame entries (workspaces) as boundaries, so they keep their input.
function entries(item, result) {
    if (!item.visible) return
    // Read wrapper positions too: mapToItem alone does not track their changes.
    const position = item.x + item.y + item.width + item.height
    if (item.barHitFrame === true) {
        result.push(item)
        return
    }
    const before = result.length
    for (const child of item.children || []) entries(child, result)
    if (item.barHitBoundary === true && result.length === before && item.item)
        result.push(item.item)
}

function partition(rects, index, width, height, atBottom) {
    const rect = rects[index]
    const left = index === 0 ? 0 : (rects[index - 1].x + rects[index - 1].width + rect.x) / 2
    const right = index === rects.length - 1 ? width : (rect.x + rect.width + rects[index + 1].x) / 2
    return { x: left - rect.x, y: atBottom ? 0 : -rect.y,
        width: Math.max(0, right - left), height: atBottom ? height - rect.y : rect.y + rect.height }
}

function bounds(content, target, atBottom) {
    const items = []
    entries(content, items)
    const rects = items.map(item => {
        const p = item.mapToItem(content, 0, 0)
        return {item: item, x: p.x, y: p.y, width: item.width, height: item.height}
    }).sort((a, b) => a.x - b.x)
    const index = rects.findIndex(rect => rect.item === target)
    return index < 0 ? Qt.rect(0, 0, target.width, target.height)
        : partition(rects, index, content.width, content.height, atBottom)
}
