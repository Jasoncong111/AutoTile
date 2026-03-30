import AppKit
import ApplicationServices
import CoreGraphics

enum WindowTilerError: LocalizedError {
    case missingScreen

    var errorDescription: String? {
        switch self {
        case .missingScreen:
            return "No active screen found"
        }
    }
}

struct WindowSnapshot {
    let windowID: Int
    let pid: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
}

struct ManagedWindow {
    let snapshot: WindowSnapshot
    let element: AXUIElement
    let frame: CGRect
}

struct WindowLayoutEntry {
    let element: AXUIElement
    let frame: CGRect
    let minimized: Bool
}

struct WindowLayoutSnapshot {
    let entries: [WindowLayoutEntry]

    var isEmpty: Bool {
        entries.isEmpty
    }
}

struct TilingInsets {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat

    static let desktopFriendly = TilingInsets(top: 6, left: 6, bottom: 6, right: 6)
}

struct GridSpec {
    let cols: Int
    let rows: Int
}

final class WindowTiler {
    private let ignoredOwners: Set<String> = [
        "Window Server",
        "Dock",
        "Control Center",
        "Notification Center",
        "AutoTile"
    ]

    private let layoutInsets = TilingInsets.desktopFriendly

    func currentSignature() -> String {
        guard let screen = activeScreen() else {
            return "no-screen"
        }

        let ids = visibleSnapshots(on: screen)
            .map(\.windowID)
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        let frame = screen.visibleFrame.integral
        return "\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.width)):\(Int(frame.height))|\(ids)"
    }

    func tileWindowsOnActiveScreen() throws -> Int {
        guard let screen = activeScreen() else {
            throw WindowTilerError.missingScreen
        }

        let windows = resolveManagedWindows(on: screen)
        guard !windows.isEmpty else {
            return 0
        }

        let usableBounds = usableBounds(for: screen)

        if windows.count == 2 {
            let frames = makeTwoWindowFrames(in: usableBounds)
            DebugLog.write("using dedicated two-window layout screen=\(NSStringFromRect(usableBounds))")
            for (window, frame) in zip(windows, frames) {
                apply(frame: frame, to: window.element)
            }
            usleep(120000)
            for (window, frame) in zip(windows, frames) {
                apply(frame: frame, to: window.element)
            }
            return windows.count
        }

        let candidateCols = candidateColumnCounts(for: windows.count, in: usableBounds)

        for cols in candidateCols {
            let spec = GridSpec(cols: cols, rows: Int(ceil(Double(windows.count) / Double(cols))))
            let plannedFrames = makeGridFrames(count: windows.count, in: usableBounds, spec: spec)
            DebugLog.write("trying spec cols=\(spec.cols) rows=\(spec.rows) screen=\(NSStringFromRect(usableBounds))")

            for (window, frame) in zip(windows, plannedFrames) {
                apply(frame: frame, to: window.element)
            }

            usleep(120000)
            for (window, frame) in zip(windows, plannedFrames) {
                apply(frame: frame, to: window.element)
            }

            usleep(80000)

            let verifiedWindows = windows.compactMap { window -> ManagedWindow? in
                guard let updatedFrame = frame(of: window.element) else {
                    return nil
                }
                return ManagedWindow(snapshot: window.snapshot, element: window.element, frame: updatedFrame)
            }

            if !hasOverlap(verifiedWindows) && fitsInsideBounds(verifiedWindows, usableBounds) {
                return windows.count
            }
        }

        let fallbackFrames = makeStackedGridFrames(count: windows.count, in: usableBounds)
        for (window, frame) in zip(windows, fallbackFrames) {
            apply(frame: frame, to: window.element)
        }

        return windows.count
    }

    func yieldDesktopOnActiveScreen() throws -> Int {
        guard let screen = activeScreen() else {
            throw WindowTilerError.missingScreen
        }

        let windows = resolveManagedWindows(on: screen)
        guard !windows.isEmpty else {
            return 0
        }

        let frames = makeDesktopYieldFrames(for: windows, in: usableBounds(for: screen))
        for (window, frame) in zip(windows, frames) {
            apply(frame: frame, to: window.element)
        }

        usleep(120000)
        for (window, frame) in zip(windows, frames) {
            apply(frame: frame, to: window.element)
        }

        return windows.count
    }

    func captureLayoutForActiveScreen() throws -> WindowLayoutSnapshot {
        guard let screen = activeScreen() else {
            throw WindowTilerError.missingScreen
        }

        let entries = resolveManagedWindows(on: screen)
            .map { WindowLayoutEntry(element: $0.element, frame: $0.frame, minimized: isMinimized($0.element)) }
        return WindowLayoutSnapshot(entries: entries)
    }

    func restoreLayout(_ snapshot: WindowLayoutSnapshot) -> Int {
        for entry in snapshot.entries {
            setMinimized(false, for: entry.element)
            apply(frame: entry.frame, to: entry.element)
            if entry.minimized {
                setMinimized(true, for: entry.element)
            }
        }
        return snapshot.entries.count
    }

    func showDesktopOnActiveScreen() throws -> Int {
        guard let screen = activeScreen() else {
            throw WindowTilerError.missingScreen
        }

        let windows = resolveManagedWindows(on: screen)
        guard !windows.isEmpty else {
            return 0
        }

        for window in windows {
            setMinimized(true, for: window.element)
        }
        return windows.count
    }

    private func activeScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSScreen.main
        }

        var bestScreen: NSScreen?
        var bestCount = -1

        for screen in screens {
            let count = visibleSnapshots(on: screen).count
            if count > bestCount {
                bestCount = count
                bestScreen = screen
            }
        }

        if let bestScreen, bestCount > 0 {
            return bestScreen
        }

        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func usableBounds(for screen: NSScreen) -> CGRect {
        screen.visibleFrame
    }

    private func resolveManagedWindows(on screen: NSScreen) -> [ManagedWindow] {
        let snapshots = visibleSnapshots(on: screen)
        DebugLog.write("visible snapshots count=\(snapshots.count)")
        for snapshot in snapshots {
            DebugLog.write("snapshot pid=\(snapshot.pid) id=\(snapshot.windowID) owner=\(snapshot.ownerName) title=\(snapshot.title) bounds=\(NSStringFromRect(snapshot.bounds))")
        }
        let snapshotsByPid = Dictionary(grouping: snapshots, by: \.pid)
        var matched: [ManagedWindow] = []

        for (pid, pidSnapshots) in snapshotsByPid {
            let app = AXUIElementCreateApplication(pid)
            let axWindows = fetchAppWindows(app)
            DebugLog.write("ax app pid=\(pid) candidate windows=\(axWindows.count)")
            for (index, window) in axWindows.enumerated() {
                let title = stringAttribute(kAXTitleAttribute as CFString, of: window) ?? ""
                let rect = frame(of: window) ?? .zero
                DebugLog.write("ax window [\(index)] pid=\(pid) title=\(title) frame=\(NSStringFromRect(rect))")
            }
            var usedIndexes = Set<Int>()

            for snapshot in pidSnapshots.sorted(by: snapshotSort) {
                guard let matchIndex = bestMatch(for: snapshot, among: axWindows, usedIndexes: usedIndexes) else {
                    DebugLog.write("unmatched snapshot pid=\(snapshot.pid) id=\(snapshot.windowID) owner=\(snapshot.ownerName) title=\(snapshot.title)")
                    continue
                }
                usedIndexes.insert(matchIndex)

                let element = axWindows[matchIndex]
                let frame = frame(of: element) ?? snapshot.bounds
                DebugLog.write("matched snapshot id=\(snapshot.windowID) -> ax[\(matchIndex)] frame=\(NSStringFromRect(frame))")
                matched.append(ManagedWindow(snapshot: snapshot, element: element, frame: frame))
            }
        }

        DebugLog.write("managed windows count=\(matched.count)")
        return matched.sorted { snapshotSort($0.snapshot, $1.snapshot) }
    }

    private func visibleSnapshots(on screen: NSScreen) -> [WindowSnapshot] {
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let screenFrame = screen.frame
        return rawList.compactMap { item in
            guard
                let owner = item[kCGWindowOwnerName as String] as? String,
                !ignoredOwners.contains(owner),
                let pid = item[kCGWindowOwnerPID as String] as? pid_t,
                pid != getpid(),
                let layer = item[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsObject = item[kCGWindowBounds as String],
                let bounds = CGRect(dictionaryRepresentation: boundsObject as! CFDictionary)
            else {
                return nil
            }

            let alpha = item[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha <= 0.01 || bounds.width < 120 || bounds.height < 80 {
                return nil
            }

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if !screenFrame.contains(center) {
                return nil
            }

            let windowID = item[kCGWindowNumber as String] as? Int ?? 0
            let title = item[kCGWindowName as String] as? String ?? ""
            return WindowSnapshot(windowID: windowID, pid: pid, ownerName: owner, title: title, bounds: bounds)
        }
    }

    private func fetchAppWindows(_ app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else {
            return []
        }

        return array.filter { window in
            !isMinimized(window) &&
            !isFullscreen(window) &&
            isCandidateWindow(window) &&
            isResizable(window) &&
            isMovable(window) &&
            frame(of: window) != nil
        }
    }

    private func bestMatch(for snapshot: WindowSnapshot, among windows: [AXUIElement], usedIndexes: Set<Int>) -> Int? {
        var bestIndex: Int?
        var bestScore = Double.greatestFiniteMagnitude

        for (index, window) in windows.enumerated() where !usedIndexes.contains(index) {
            guard let frame = frame(of: window) else {
                continue
            }

            let axTitle = stringAttribute(kAXTitleAttribute as CFString, of: window) ?? ""
            let titlePenalty: Double
            if snapshot.title.isEmpty || axTitle.isEmpty {
                titlePenalty = 15
            } else if snapshot.title == axTitle {
                titlePenalty = 0
            } else if snapshot.title.contains(axTitle) || axTitle.contains(snapshot.title) {
                titlePenalty = 8
            } else {
                titlePenalty = 40
            }

            let originDistance = hypot(frame.origin.x - snapshot.bounds.origin.x, frame.origin.y - snapshot.bounds.origin.y)
            let sizeDistance = hypot(frame.width - snapshot.bounds.width, frame.height - snapshot.bounds.height)
            let centerDistance = hypot(frame.midX - snapshot.bounds.midX, frame.midY - snapshot.bounds.midY)
            let score = titlePenalty + originDistance * 0.2 + sizeDistance * 0.25 + centerDistance * 0.35

            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestScore < 260 ? bestIndex : nil
    }

    private func snapshotSort(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
        if abs(lhs.bounds.minX - rhs.bounds.minX) > 24 {
            return lhs.bounds.minX < rhs.bounds.minX
        }
        if abs(lhs.bounds.minY - rhs.bounds.minY) > 24 {
            return lhs.bounds.minY < rhs.bounds.minY
        }
        return lhs.ownerName < rhs.ownerName
    }

    private func isCandidateWindow(_ window: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as CFString, of: window)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: window)
        guard role == kAXWindowRole as String else {
            return false
        }

        if subrole == nil {
            return true
        }

        let allowedSubroles: Set<String> = [
            kAXStandardWindowSubrole as String,
            "AXDialog",
            "AXSystemDialog",
            "AXFloatingWindow"
        ]
        return allowedSubroles.contains(subrole!)
    }

    private func isResizable(_ window: AXUIElement) -> Bool {
        isAttributeSettable(kAXSizeAttribute as CFString, on: window)
    }

    private func isMovable(_ window: AXUIElement) -> Bool {
        isAttributeSettable(kAXPositionAttribute as CFString, on: window)
    }

    private func candidateColumnCounts(for count: Int, in visibleBounds: CGRect) -> [Int] {
        let preferred = preferredGridSpec(count: count, in: visibleBounds)
        var candidates: [Int] = []
        for cols in stride(from: preferred.cols, through: 1, by: -1) {
            if !candidates.contains(cols) {
                candidates.append(cols)
            }
        }
        let maxCols = maximumColumns(for: count)
        if preferred.cols < maxCols {
            for cols in (preferred.cols + 1)...maxCols where !candidates.contains(cols) {
                candidates.append(cols)
            }
        }
        return candidates
    }

    private func maximumColumns(for count: Int) -> Int {
        switch count {
        case 0...2:
            return max(1, count)
        case 3...4:
            return 2
        case 5...9:
            return 3
        default:
            return 4
        }
    }

    private func preferredGridSpec(count: Int, in visibleBounds: CGRect) -> GridSpec {
        let usable = CGRect(
            x: visibleBounds.minX + layoutInsets.left,
            y: visibleBounds.minY + layoutInsets.top,
            width: max(320, visibleBounds.width - layoutInsets.left - layoutInsets.right),
            height: max(240, visibleBounds.height - layoutInsets.top - layoutInsets.bottom)
        )

        if count == 1 {
            return GridSpec(cols: 1, rows: 1)
        }

        if count == 2 {
            if usable.width >= usable.height {
                return GridSpec(cols: 2, rows: 1)
            } else {
                return GridSpec(cols: 1, rows: 2)
            }
        }

        let gap: CGFloat = 12
        var bestCols = 1
        var bestRows = count
        var bestScore = CGFloat.greatestFiniteMagnitude
        let maxCols = maximumColumns(for: count)
        let screenAspect = usable.width / usable.height

        for cols in 1...maxCols {
            let rows = Int(ceil(Double(count) / Double(cols)))
            let cellWidth = (usable.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
            let cellHeight = (usable.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            guard cellWidth > 200, cellHeight > 140 else {
                continue
            }

            let aspect = cellWidth / cellHeight
            let emptySlots = cols * rows - count
            let aspectTarget = min(1.6, max(0.9, screenAspect / 1.6))
            let aspectScore = abs(aspect - aspectTarget)
            let balanceScore = abs(CGFloat(cols) - CGFloat(rows) * screenAspect * 0.7) * 0.18
            let score = aspectScore + balanceScore + CGFloat(emptySlots) * 0.22
            if score < bestScore {
                bestScore = score
                bestCols = cols
                bestRows = rows
            }
        }

        return GridSpec(cols: bestCols, rows: bestRows)
    }

    private func makeGridFrames(count: Int, in visibleBounds: CGRect, spec: GridSpec) -> [CGRect] {
        let usable = CGRect(
            x: visibleBounds.minX + layoutInsets.left,
            y: visibleBounds.minY + layoutInsets.top,
            width: max(320, visibleBounds.width - layoutInsets.left - layoutInsets.right),
            height: max(240, visibleBounds.height - layoutInsets.top - layoutInsets.bottom)
        )

        if count == 1 {
            return [usable]
        }

        let gap: CGFloat = 8
        let totalGapWidth = CGFloat(max(0, spec.cols - 1)) * gap
        let totalGapHeight = CGFloat(max(0, spec.rows - 1)) * gap
        let baseCellWidth = floor((usable.width - totalGapWidth) / CGFloat(spec.cols))
        let baseCellHeight = floor((usable.height - totalGapHeight) / CGFloat(spec.rows))
        let lastColWidth = usable.width - CGFloat(spec.cols - 1) * baseCellWidth - totalGapWidth
        let lastRowHeight = usable.height - CGFloat(spec.rows - 1) * baseCellHeight - totalGapHeight
        let rowHeights = (0..<spec.rows).map { $0 == spec.rows - 1 ? lastRowHeight : baseCellHeight }

        var frames: [CGRect] = []
        for index in 0..<count {
            let row = index / spec.cols
            let col = index % spec.cols
            let width = col == spec.cols - 1 ? lastColWidth : baseCellWidth
            let height = rowHeights[row]
            let x = usable.minX + CGFloat(col) * (baseCellWidth + gap)
            let consumedAbove = rowHeights.prefix(row).reduce(0, +) + CGFloat(row) * gap
            let y = usable.maxY - consumedAbove - height
            frames.append(
                CGRect(
                    x: round(x),
                    y: round(y),
                    width: round(width),
                    height: round(height)
                )
            )
        }
        return frames
    }

    private func makeTwoWindowFrames(in visibleBounds: CGRect) -> [CGRect] {
        let usable = CGRect(
            x: visibleBounds.minX + layoutInsets.left,
            y: visibleBounds.minY + layoutInsets.top,
            width: max(320, visibleBounds.width - layoutInsets.left - layoutInsets.right),
            height: max(240, visibleBounds.height - layoutInsets.top - layoutInsets.bottom)
        )

        let gap: CGFloat = 8

        if usable.width >= usable.height {
            let leftWidth = floor((usable.width - gap) / 2)
            let rightWidth = usable.width - leftWidth - gap
            return [
                CGRect(
                    x: round(usable.minX),
                    y: round(usable.minY),
                    width: round(leftWidth),
                    height: round(usable.height)
                ),
                CGRect(
                    x: round(usable.minX + leftWidth + gap),
                    y: round(usable.minY),
                    width: round(rightWidth),
                    height: round(usable.height)
                )
            ]
        } else {
            let topHeight = floor((usable.height - gap) / 2)
            let bottomHeight = usable.height - topHeight - gap
            return [
                CGRect(
                    x: round(usable.minX),
                    y: round(usable.maxY - topHeight),
                    width: round(usable.width),
                    height: round(topHeight)
                ),
                CGRect(
                    x: round(usable.minX),
                    y: round(usable.minY),
                    width: round(usable.width),
                    height: round(bottomHeight)
                )
            ]
        }
    }

    private func makeDesktopYieldFrames(for windows: [ManagedWindow], in visibleBounds: CGRect) -> [CGRect] {
        let outer = CGRect(
            x: visibleBounds.minX + 6,
            y: visibleBounds.minY + 6,
            width: max(320, visibleBounds.width - 12),
            height: max(240, visibleBounds.height - 12)
        )

        let centerWidth = max(280, outer.width * 0.42)
        let centerHeight = max(220, outer.height * 0.42)
        let center = CGRect(
            x: outer.midX - centerWidth / 2,
            y: outer.midY - centerHeight / 2,
            width: centerWidth,
            height: centerHeight
        )
        let gap: CGFloat = 8

        let leftRect = CGRect(
            x: outer.minX,
            y: outer.minY,
            width: max(180, center.minX - outer.minX - gap),
            height: outer.height
        )
        let rightRect = CGRect(
            x: center.maxX + gap,
            y: outer.minY,
            width: max(180, outer.maxX - center.maxX - gap),
            height: outer.height
        )
        let topRect = CGRect(
            x: center.minX,
            y: center.maxY + gap,
            width: center.width,
            height: max(110, outer.maxY - center.maxY - gap)
        )
        let bottomRect = CGRect(
            x: center.minX,
            y: outer.minY,
            width: center.width,
            height: max(110, center.minY - outer.minY - gap)
        )

        let sideOrder = balancedSideOrder(count: windows.count)
        var buckets: [String: [ManagedWindow]] = ["top": [], "right": [], "bottom": [], "left": []]
        for (index, window) in windows.enumerated() {
            buckets[sideOrder[index], default: []].append(window)
        }

        var assigned: [Int: CGRect] = [:]
        let indexByWindowID = Dictionary(uniqueKeysWithValues: windows.enumerated().map { ($1.snapshot.windowID, $0) })
        layoutLinearSide(windows: buckets["top"] ?? [], in: topRect, axis: .horizontal, indexByWindowID: indexByWindowID, assigned: &assigned)
        layoutLinearSide(windows: buckets["bottom"] ?? [], in: bottomRect, axis: .horizontal, indexByWindowID: indexByWindowID, assigned: &assigned)
        layoutLinearSide(windows: buckets["left"] ?? [], in: leftRect, axis: .vertical, indexByWindowID: indexByWindowID, assigned: &assigned)
        layoutLinearSide(windows: buckets["right"] ?? [], in: rightRect, axis: .vertical, indexByWindowID: indexByWindowID, assigned: &assigned)

        return windows.enumerated().map { index, window in assigned[index] ?? window.frame }
    }

    private enum LayoutAxis {
        case horizontal
        case vertical
    }

    private func balancedSideOrder(count: Int) -> [String] {
        let cycle = ["left", "right", "left", "right", "top", "bottom"]
        return (0..<count).map { cycle[$0 % cycle.count] }
    }

    private func layoutLinearSide(
        windows: [ManagedWindow],
        in area: CGRect,
        axis: LayoutAxis,
        indexByWindowID: [Int: Int],
        assigned: inout [Int: CGRect]
    ) {
        guard !windows.isEmpty else {
            return
        }

        let gap: CGFloat = 8
        let indexed = windows.enumerated()

        switch axis {
        case .horizontal:
            let cellWidth = floor((area.width - CGFloat(max(0, windows.count - 1)) * gap) / CGFloat(windows.count))
            for (localIndex, pair) in indexed {
                let x = area.minX + CGFloat(localIndex) * (cellWidth + gap)
                guard let globalIndex = indexByWindowID[pair.snapshot.windowID] else { continue }
                assigned[globalIndex] = CGRect(
                    x: round(x),
                    y: round(area.minY),
                    width: round(max(160, cellWidth)),
                    height: round(max(120, area.height))
                )
            }
        case .vertical:
            let cellHeight = floor((area.height - CGFloat(max(0, windows.count - 1)) * gap) / CGFloat(windows.count))
            for (localIndex, pair) in indexed {
                let y = area.maxY - CGFloat(localIndex + 1) * cellHeight - CGFloat(localIndex) * gap
                guard let globalIndex = indexByWindowID[pair.snapshot.windowID] else { continue }
                assigned[globalIndex] = CGRect(
                    x: round(area.minX),
                    y: round(y),
                    width: round(max(180, area.width)),
                    height: round(max(90, cellHeight))
                )
            }
        }
    }

    private func makeStackedGridFrames(count: Int, in visibleBounds: CGRect) -> [CGRect] {
        let usable = CGRect(
            x: visibleBounds.minX + layoutInsets.left,
            y: visibleBounds.minY + layoutInsets.top,
            width: max(320, visibleBounds.width - layoutInsets.left - layoutInsets.right),
            height: max(240, visibleBounds.height - layoutInsets.top - layoutInsets.bottom)
        )

        let cols = max(1, Int(floor(sqrt(Double(count)))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let gap: CGFloat = 8
        let cellWidth = max(240, (usable.width - CGFloat(cols - 1) * gap) / CGFloat(cols))
        let cellHeight = max(180, (usable.height - CGFloat(rows - 1) * gap) / CGFloat(rows))

        var frames: [CGRect] = []
        for index in 0..<count {
            let row = index / cols
            let col = index % cols
            frames.append(
                CGRect(
                    x: round(usable.minX + CGFloat(col) * (cellWidth + gap)),
                    y: round(usable.maxY - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap),
                    width: round(min(cellWidth, usable.maxX - (usable.minX + CGFloat(col) * (cellWidth + gap)))),
                    height: round(min(cellHeight, usable.maxY - (usable.minY + CGFloat(row) * (cellHeight + gap))))
                )
            )
        }
        return frames
    }

    private func hasOverlap(_ windows: [ManagedWindow]) -> Bool {
        for index in 0..<windows.count {
            for otherIndex in (index + 1)..<windows.count {
                if windows[index].frame.intersects(windows[otherIndex].frame) {
                    return true
                }
            }
        }
        return false
    }

    private func fitsInsideBounds(_ windows: [ManagedWindow], _ bounds: CGRect) -> Bool {
        for window in windows {
            if window.frame.minX < bounds.minX - 1 || window.frame.minY < bounds.minY - 1 {
                return false
            }
            if window.frame.maxX > bounds.maxX + 1 || window.frame.maxY > bounds.maxY + 1 {
                return false
            }
        }
        return true
    }

    private func apply(frame: CGRect, to window: AXUIElement) {
        var point = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)

        if let axPosition = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axPosition)
        }
        if let axSize = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axSize)
        }
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard
            let position = pointAttribute(kAXPositionAttribute as CFString, of: window),
            let size = sizeAttribute(kAXSizeAttribute as CFString, of: window)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        boolAttribute(kAXMinimizedAttribute as CFString, of: window) ?? false
    }

    private func setMinimized(_ minimized: Bool, for window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized as CFBoolean)
    }

    private func isFullscreen(_ window: AXUIElement) -> Bool {
        boolAttribute("AXFullScreen" as CFString, of: window) ?? false
    }

    private func stringAttribute(_ key: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ key: CFString, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key, &value)
        guard result == .success else {
            return nil
        }
        return value as? Bool
    }

    private func pointAttribute(_ key: CFString, of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key, &value)
        guard result == .success, let axValue = value else {
            return nil
        }

        let typedValue = axValue as! AXValue
        guard AXValueGetType(typedValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(typedValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ key: CFString, of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key, &value)
        guard result == .success, let axValue = value else {
            return nil
        }

        let typedValue = axValue as! AXValue
        guard AXValueGetType(typedValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(typedValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func isAttributeSettable(_ key: CFString, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, key, &settable)
        return result == .success && settable.boolValue
    }
}
