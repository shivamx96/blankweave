.pragma library

function canDelete(cursor, length, start, end) {
    return cursor === length && start === end
}

function showEmpty(count, clipboard, loaded, loading) {
    return count === 0 && (!clipboard || (loaded && !loading))
}
