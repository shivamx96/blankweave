.pragma library
function running(job) { return Boolean(job && ["starting", "running"].includes(job.phase)); }
function phase(job) {
    return job ? ({starting:"Starting",running:"Running",completed:"Completed",failed:"Failed",
        cancelled:"Cancelled",interrupted:"Interrupted"})[job.phase] || "Unknown status" : "";
}
function elapsed(job, now) {
    if (!job || !job.started) return "";
    var start = Date.parse(job.started);
    var end = running(job) ? now : Date.parse(job.finished || "");
    if (!isFinite(start) || !isFinite(end)) return "";
    var seconds = Math.max(0, Math.floor((end - start) / 1000));
    return seconds < 60 ? seconds + "s" : seconds < 3600 ? Math.floor(seconds / 60) + "m " + seconds % 60 + "s"
        : Math.floor(seconds / 3600) + "h " + Math.floor(seconds % 3600 / 60) + "m";
}
