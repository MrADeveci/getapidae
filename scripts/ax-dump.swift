// ax-dump.swift — dump the accessibility tree of a running app.
// Usage: swift scripts/ax-dump.swift <bundle-id-or-name> [maxDepth]
// Requires Accessibility permission for the host (Terminal).

import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: ax-dump <bundle-id-or-name> [maxDepth]")
    exit(1)
}
let target = args[1]
let maxDepth = args.count >= 3 ? Int(args[2]) ?? 12 : 12

guard AXIsProcessTrusted() else {
    print("Accessibility permission missing for this terminal. Grant it in System Settings > Privacy & Security > Accessibility, then rerun.")
    exit(2)
}

let apps = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == target || $0.localizedName == target
}
guard let app = apps.first else {
    print("No running app matching '\(target)'. Running apps with 'claude' in the name/id:")
    for a in NSWorkspace.shared.runningApplications
    where (a.bundleIdentifier ?? "").lowercased().contains("claude") || (a.localizedName ?? "").lowercased().contains("claude") {
        print("  \(a.processIdentifier)  \(a.bundleIdentifier ?? "-")  \(a.localizedName ?? "-")")
    }
    exit(3)
}
print("App: \(app.localizedName ?? "-") pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "-")")

let axApp = AXUIElementCreateApplication(app.processIdentifier)
// Electron/Chromium only builds the web AX tree when asked.
let r1 = AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
let r2 = AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
print("set AXManualAccessibility=\(r1.rawValue) AXEnhancedUserInterface=\(r2.rawValue)")
Thread.sleep(forTimeInterval: 3.0)

func attr(_ el: AXUIElement, _ name: String) -> Any? {
    var v: CFTypeRef?
    let r = AXUIElementCopyAttributeValue(el, name as CFString, &v)
    return r == .success ? v : nil
}
func str(_ v: Any?) -> String {
    guard let v else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    if CFGetTypeID(v as CFTypeRef) == AXValueGetTypeID() {
        let a = v as! AXValue
        var p = CGPoint.zero; var s = CGSize.zero
        if AXValueGetValue(a, .cgPoint, &p) { return "(\(Int(p.x)),\(Int(p.y)))" }
        if AXValueGetValue(a, .cgSize, &s) { return "\(Int(s.width))x\(Int(s.height))" }
    }
    return String(describing: v).prefix(60).description
}

var count = 0
func walk(_ el: AXUIElement, depth: Int) {
    guard depth <= maxDepth, count < 4000 else { return }
    count += 1
    let role = str(attr(el, kAXRoleAttribute))
    let sub = str(attr(el, kAXSubroleAttribute))
    let title = str(attr(el, kAXTitleAttribute))
    let desc = str(attr(el, kAXDescriptionAttribute))
    let value = str(attr(el, kAXValueAttribute)).replacingOccurrences(of: "\n", with: "⏎")
    let help = str(attr(el, kAXHelpAttribute))
    let ident = str(attr(el, "AXIdentifier"))
    let enabled = str(attr(el, kAXEnabledAttribute))
    var line = String(repeating: "  ", count: depth) + role
    if !sub.isEmpty { line += "/\(sub)" }
    if !title.isEmpty { line += " title=\"\(title.prefix(80))\"" }
    if !desc.isEmpty { line += " desc=\"\(desc.prefix(80))\"" }
    if !value.isEmpty { line += " value=\"\(value.prefix(80))\"" }
    if !help.isEmpty { line += " help=\"\(help.prefix(60))\"" }
    if !ident.isEmpty { line += " id=\"\(ident)\"" }
    if enabled == "0" { line += " disabled" }
    print(line)
    if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for c in children { walk(c, depth: depth + 1) }
    }
}

// Walk only the windows (the menu bar is noise). Retry while the web area is still empty.
for attempt in 1...4 {
    count = 0
    let windows = (attr(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    print("attempt \(attempt): \(windows.count) window(s)")
    for w in windows { walk(w, depth: 1) }
    if count > 40 || attempt == 4 { break }
    print("(web content still empty, waiting)")
    Thread.sleep(forTimeInterval: 3.0)
}
print("-- \(count) elements --")
