.pragma library

function decode(text) {
    // Discard only complete leading noise lines, never braces inside a log
    // message. Trailing garbage or a malformed JSON-looking line is an error.
    const lines = String(text || "").trim().split("\n")
    while (lines.length && !/^[\[{]/.test(lines[0].trim())) lines.shift()
    const payload = lines.join("\n")
    const data = JSON.parse(payload)
    if (data === null || typeof data !== "object") throw new Error("Expected JSON")
    return {payload: payload, data: data}
}
