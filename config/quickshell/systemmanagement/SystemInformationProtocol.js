.pragma library

function informationIds() {
    return ["os-name", "os-version", "kernel-release", "architecture", "hardware-vendor", "hardware-model",
        "cpu-model", "logical-cpus", "memory-total-bytes", "memory-available-bytes", "swap-total-bytes",
        "swap-free-bytes", "uptime-seconds"];
}
function securityIds() { return ["selinux", "secure-boot", "firewalld", "root-encryption", "screen-lock"]; }
function stateIds() { return informationIds().concat(["filesystem-summary"], securityIds()); }
function owners() { return ["information", "storage", "security", "diagnostics"]; }
function owner(identifier) {
    if (informationIds().indexOf(identifier) >= 0) return "information";
    if (securityIds().indexOf(identifier) >= 0) return "security";
    return identifier === "filesystem-summary" ? "storage" : "";
}
function providerClass(identifier) {
    if (identifier === "diagnostics") return "user-session";
    return owners().indexOf(identifier) >= 0 ? "read-only" : "delegated";
}
function uint64(value) {
    return typeof value === "string" && /^(0|[1-9][0-9]*)$/.test(value)
        && (value.length < 20 || (value.length === 20 && value <= "18446744073709551615"));
}
function validValue(identifier, status, value) {
    if (status !== "available") return value === "unknown";
    if (identifier === "filesystem-summary") return uint64(value) && Number(value) <= 256;
    if (["logical-cpus", "memory-total-bytes", "memory-available-bytes", "swap-total-bytes",
            "swap-free-bytes", "uptime-seconds"].indexOf(identifier) >= 0)
        return uint64(value) && (identifier !== "logical-cpus" || value !== "0");
    if (identifier === "selinux") return ["enforcing", "permissive", "disabled"].indexOf(value) >= 0;
    if (identifier === "root-encryption") return value === "encrypted" || value === "unencrypted";
    if (securityIds().indexOf(identifier) >= 0) return value === "enabled" || value === "disabled";
    return typeof value === "string" && value.trim().length > 0;
}
function validFilesystem(fields) {
    if (!uint64(fields[1]) || (fields[2] !== "available" && fields[2] !== "partial")
            || !fields[3] || !fields[4] || !fields[5]) return false;
    const counters = fields.slice(6, 9);
    return counters.every(value => uint64(value) || (fields[2] === "partial" && value === "unknown"))
        && (fields[2] !== "partial" || counters.indexOf("unknown") >= 0);
}
function filesystem(fields) {
    return { id: fields[1], status: fields[2], source: fields[3], target: fields[4], fstype: fields[5],
        sizeBytes: fields[6], usedBytes: fields[7], availableBytes: fields[8], detail: fields[9] };
}
