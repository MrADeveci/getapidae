import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "AXTreeInspector")

/// Walks another application's accessibility tree looking for an element that satisfies
/// a predicate. Depth-first, capped by element count and depth so a huge web view
/// cannot run away with the CPU. Requires Accessibility permission.
///
/// Electron apps (Claude included) only build the web content's accessibility tree
/// when a client asks for it, so `AXManualAccessibility` is set on every visit.
enum AXTreeInspector {
    static let defaultMaxElements = 4000
    static let defaultMaxDepth = 48
    static let messagingTimeout: Float = 1.0

    /// Returns the predicate's first non-nil result, or nil if nothing matched.
    static func firstMatch(
        pid: pid_t,
        maxElements: Int = defaultMaxElements,
        maxDepth: Int = defaultMaxDepth,
        predicate: (AXElementSummary) -> String?
    ) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
            return nil
        }

        var visited = 0
        var stack: [(AXUIElement, Int)] = windows.reversed().map { ($0, 0) }
        while let (element, depth) = stack.popLast() {
            visited += 1
            if visited > maxElements {
                logger.debug("Element cap reached (\(maxElements)) without a match")
                return nil
            }
            if let hit = predicate(summary(of: element)) { return hit }
            guard depth < maxDepth,
                  let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            for child in children.reversed() { stack.append((child, depth + 1)) }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        return ""
    }

    private static func summary(of element: AXUIElement) -> AXElementSummary {
        AXElementSummary(
            role: string(attribute(element, kAXRoleAttribute)),
            subrole: string(attribute(element, kAXSubroleAttribute)),
            title: string(attribute(element, kAXTitleAttribute)),
            description: string(attribute(element, kAXDescriptionAttribute)),
            value: ""
        )
    }
}
