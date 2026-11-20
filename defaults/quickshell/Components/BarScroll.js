.pragma library

function volume(current, steps) {
    if (!steps || (steps > 0 && current >= 1)) return current
    return Math.max(0, steps < 0 ? current + steps * 0.05 : Math.min(1, current + steps * 0.05))
}
