import AppKit
import ApplicationServices
import CoreGraphics

func pointAttribute(_ key: CFString, of element: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key, &value)
    guard result == .success, let axValue = value else { return nil }
    let typedValue = axValue as! AXValue
    guard AXValueGetType(typedValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(typedValue, .cgPoint, &point) else { return nil }
    return point
}

func sizeAttribute(_ key: CFString, of element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key, &value)
    guard result == .success, let axValue = value else { return nil }
    let typedValue = axValue as! AXValue
    guard AXValueGetType(typedValue) == .cgSize else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(typedValue, .cgSize, &size) else { return nil }
    return size
}

func stringAttribute(_ key: CFString, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key, &value)
    guard result == .success else { return nil }
    return value as? String
}

func boolAttribute(_ key: CFString, of element: AXUIElement) -> Bool? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key, &value)
    guard result == .success else { return nil }
    return value as? Bool
}

func frame(of window: AXUIElement) -> CGRect? {
    guard
        let position = pointAttribute(kAXPositionAttribute as CFString, of: window),
        let size = sizeAttribute(kAXSizeAttribute as CFString, of: window)
    else { return nil }
    return CGRect(origin: position, size: size)
}

let screen = NSScreen.main ?? NSScreen.screens.first
print("Active screen: \(String(describing: screen?.frame))")

print("\nCGWindow list:")
if let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
    for item in rawList {
        let owner = item[kCGWindowOwnerName as String] as? String ?? "?"
        let title = item[kCGWindowName as String] as? String ?? ""
        let pid = item[kCGWindowOwnerPID as String] as? pid_t ?? 0
        let layer = item[kCGWindowLayer as String] as? Int ?? -1
        let alpha = item[kCGWindowAlpha as String] as? Double ?? 0
        let wid = item[kCGWindowNumber as String] as? Int ?? 0
        let boundsObject = item[kCGWindowBounds as String]
        let bounds = boundsObject.flatMap { CGRect(dictionaryRepresentation: $0 as! CFDictionary) } ?? .zero
        print("CG pid=\(pid) id=\(wid) owner=\(owner) layer=\(layer) alpha=\(alpha) title=\(title) bounds=\(NSStringFromRect(bounds))")
    }
}

print("\nAX windows by app:")
for app in NSWorkspace.shared.runningApplications.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
    guard let name = app.localizedName, !app.isTerminated else { continue }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
    guard result == .success, let windows = value as? [AXUIElement], !windows.isEmpty else { continue }
    print("APP \(name) pid=\(app.processIdentifier) windows=\(windows.count)")
    for (index, window) in windows.enumerated() {
        let title = stringAttribute(kAXTitleAttribute as CFString, of: window) ?? ""
        let role = stringAttribute(kAXRoleAttribute as CFString, of: window) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: window) ?? ""
        let minimized = boolAttribute(kAXMinimizedAttribute as CFString, of: window) ?? false
        let fullscreen = boolAttribute("AXFullScreen" as CFString, of: window) ?? false
        let rect = frame(of: window) ?? .zero
        print("  [\(index)] role=\(role) subrole=\(subrole) min=\(minimized) full=\(fullscreen) title=\(title) frame=\(NSStringFromRect(rect))")
    }
}
