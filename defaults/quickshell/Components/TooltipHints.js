function line(rightClick, scroll) {
    const hints = []
    if (rightClick) hints.push("Right-click: " + rightClick)
    if (scroll) hints.push("Scroll: " + scroll)
    return hints.join(" · ")
}
function text(body, rightClick, scroll) {
    const hint = line(rightClick, scroll)
    return body + (hint ? (body ? "\n" : "") + hint : "")
}
