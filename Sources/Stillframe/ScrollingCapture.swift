import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class ScrollingCapture: ObservableObject {
    @Published var count = 0
    @Published var isBusy = false
    @Published var message = "Capturing the first frame…"
    @Published var manual = false
    @Published var overlapPercent = 50.0
    @Published private(set) var result: CGImage?
    @Published private(set) var framePreview: NSImage?
    @Published private(set) var isAutoScrolling = false
    private var region = CGRect.zero
    private var targetWindow: ScrollTarget?
    private var captureSource: (SCContentFilter, SCStreamConfiguration)?
    private var panel: NSPanel?
    private var picker: RegionPicker?
    var addShortcut = "⌃⇧⌘6"
    var finishShortcut = "⌃⇧⌘Return"
    var onFinish: ((NSImage, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((String) -> Void)?
    var isActive: Bool { panel != nil || picker != nil }

    private struct ScrollTarget: Equatable {
        let id: CGWindowID
        let bounds: CGRect
    }

    func begin(seed: NSImage? = nil, region seedRegion: CGRect? = nil) {
        guard !isActive else { panel?.orderFrontRegardless(); return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { onCancel?(); return }
        let initial = seed.flatMap { ImageRenderer.bitmap($0)?.cgImage }
        if seed != nil && initial == nil {
            onCancel?(); onError?(StitchError.invalidImage.localizedDescription); return
        }
        result = initial; framePreview = seed; count = seed == nil ? 0 : 1; manual = false
        captureSource = nil
        targetWindow = nil
        message = seed == nil ? "Capturing the first frame…" : "Your screenshot is the first frame."
        if let seedRegion, seedRegion.width > 0, seedRegion.height > 0, seed != nil {
            region = seedRegion
            targetWindow = windowAtRegionCenter()
            showControls(screen: screen)
        } else {
            let picker = RegionPicker(); self.picker = picker
            picker.choose { [weak self] rect in
                guard let self else { return }
                self.picker = nil
                guard let rect else { self.result = nil; self.framePreview = nil; self.count = 0; self.onCancel?(); return }
                self.region = rect
                self.targetWindow = self.windowAtRegionCenter()
                self.showControls(screen: screen)
                if self.result == nil { self.addFrame() }
            }
        }
    }
    private func showControls(screen: NSScreen) {
        let screenTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: region.midX, y: screenTop - region.midY)) } ?? screen
        let visible = screen.visibleFrame
        let x = region.midX <= visible.midX ? visible.maxX - 430 : visible.minX + 30
        let control = NSPanel(contentRect: NSRect(x: x, y: visible.minY + 24, width: 400, height: 330), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        control.title = "Scrolling Capture"; control.level = .floating; control.isReleasedWhenClosed = false
        control.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: ScrollControls(session: self))
        // A tall stitched image must never change the floating panel's size.
        hosting.sizingOptions = []
        control.contentView = hosting
        control.setContentSize(NSSize(width: 400, height: 330))
        panel = control; NSApp.unhide(nil); control.orderFrontRegardless()
    }

    private func windowAtRegionCenter() -> ScrollTarget? {
        let point = CGPoint(x: region.midX, y: region.midY)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        for window in windows ?? [] {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  window[kCGWindowOwnerPID as String] as? Int32 != ownPID,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(point) else { continue }
            return ScrollTarget(id: id, bounds: rect)
        }
        return nil
    }

    func scrollAndCapture(toEnd: Bool = false) {
        guard !isBusy, panel != nil else { return }
        guard result != nil else { addFrame(); return }
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            message = "Allow Stillframe in Privacy & Security → Accessibility, or scroll manually and choose Add Current Frame."
            return
        }
        addFrame(scrolling: true, toEnd: toEnd)
    }

    func stopAutoScrolling() { isAutoScrolling = false }

    func addFrame(scrolling: Bool = false, toEnd: Bool = false) {
        guard !isBusy, panel != nil else { return }
        isBusy = true
        isAutoScrolling = toEnd
        message = scrolling ? "Scrolling and capturing…" : "Capturing the current frame…"
        Task {
            defer { isBusy = false; isAutoScrolling = false }
            do {
                let (filter, config) = try await screenshotSource()
                while !toEnd || isAutoScrolling {
                    if scrolling, try await scrollTarget() == false { return }
                    let frame = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    if scrolling, windowAtRegionCenter() != targetWindow {
                        message = "The original window changed. Bring it back into view before continuing."
                        return
                    }
                    let overlap = manual && !scrolling ? Int(Double(frame.height) * overlapPercent / 100) : nil
                    if let previous = result {
                        result = try await Task.detached(priority: .userInitiated) {
                            try ScrollStitcher.join(previous, frame, manualOverlap: overlap)
                        }.value
                    } else { result = frame }
                    framePreview = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
                    count += 1
                    if !toEnd { break }
                    message = "Scrolling and capturing…"
                }
                message = toEnd ? "Capture paused. Continue or finish to save." : "Frame \(count) added."
            } catch StitchError.noMovement where scrolling {
                message = "No new content detected. If you’re at the bottom, choose Finish. Otherwise, scroll manually and add the current frame."
            } catch let error as NSError where error.domain == SCStreamErrorDomain
                && error.code == SCStreamError.Code.userDeclined.rawValue {
                let recovery = "macOS denied screen capture for this copy of Stillframe. In Screen & System Audio Recording, remove any old Stillframe entry, add this Stillframe.app, then quit and reopen it."
                message = recovery
                if result == nil {
                    isBusy = false
                    cancel()
                    onError?(recovery)
                }
            } catch { message = error.localizedDescription }
        }
    }

    private func scrollTarget() async throws -> Bool {
        let distance = Int32(max(1, (region.height * 0.45).rounded(.down)))
        guard let targetWindow, windowAtRegionCenter() == targetWindow,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: -distance, wheel2: 0, wheel3: 0) else {
            message = "Bring the original window back into view, or scroll manually and choose Add Current Frame."
            return false
        }
        // Let the wheel event reach the target even if the floating panel covers its center.
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let panelPoint = CGPoint(x: region.midX, y: screenTop - region.midY)
        if panel?.frame.contains(panelPoint) == true { panel?.ignoresMouseEvents = true }
        defer { panel?.ignoresMouseEvents = false }
        event.location = CGPoint(x: region.midX, y: region.midY)
        event.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(400))
        return true
    }

    private func screenshotSource() async throws -> (SCContentFilter, SCStreamConfiguration) {
        if let captureSource { return captureSource }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { CGDisplayBounds($0.displayID).contains(region) }) else {
            throw NSError(domain: "Stillframe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Keep the selected region on one connected display."])
        }
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let bounds = CGDisplayBounds(display.displayID)
        let config = SCStreamConfiguration()
        config.sourceRect = region.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((region.width * scale).rounded())
        config.height = Int((region.height * scale).rounded())
        config.showsCursor = false
        captureSource = (filter, config)
        return (filter, config)
    }

    func finish() {
        guard !isBusy, panel != nil, let result else { return }
        panel?.close(); panel = nil; self.result = nil; framePreview = nil; count = 0
        captureSource = nil
        onFinish?(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)), region)
    }
    func cancel() {
        guard !isBusy else { return }
        if let picker { picker.cancel(); return }
        panel?.close(); panel = nil; result = nil; framePreview = nil; count = 0; captureSource = nil; onCancel?()
    }
}

private struct ScrollControls: View {
    @ObservedObject var session: ScrollingCapture
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(session.count) frames", systemImage: "rectangle.stack").font(.headline)
                if session.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                if let image = session.framePreview {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: 112, height: 56, alignment: .trailing)
                        .accessibilityLabel("Latest captured frame")
                }
            }
            Text(session.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            Toggle("Set overlap manually", isOn: $session.manual).disabled(session.isBusy)
            if session.manual {
                HStack { Slider(value: $session.overlapPercent, in: 10...90, step: 1).accessibilityLabel("Frame overlap"); Text("\(Int(session.overlapPercent))%") }
                    .disabled(session.isBusy)
            }
            Text("Capture to End scrolls from here. When it stops, choose Finish to save and copy.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { session.cancel() }.keyboardShortcut(.cancelAction)
                Button("Add Current Frame") { session.addFrame() }
                    .help("Capture the visible region after scrolling manually")
                Spacer()
                Button("Finish") { session.finish() }
                    .help("Save and copy · " + session.finishShortcut)
                    .disabled(session.result == nil)
            }.disabled(session.isBusy)
            HStack {
                Button("Scroll & Capture") { session.scrollAndCapture() }
                    .help("Capture the next section · " + session.addShortcut)
                    .disabled(session.isBusy || session.result == nil)
                Spacer()
                if session.isAutoScrolling {
                    Button("Stop Scrolling") { session.stopAutoScrolling() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Capture to End") { session.scrollAndCapture(toEnd: true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isBusy || session.result == nil)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
final class RegionPicker {
    private var panel: NSPanel?
    private var completion: ((CGRect?) -> Void)?
    func choose(completion: @escaping (CGRect?) -> Void) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { completion(nil); return }
        self.completion = completion
        let chooser = RegionSelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        chooser.title = "Select Capture Region"
        chooser.level = .screenSaver; chooser.isOpaque = false; chooser.backgroundColor = .clear
        chooser.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        chooser.isReleasedWhenClosed = false
        let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onSelect = { [weak self] rect in
            guard let self else { return }
            let global = rect?.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            let result = global.map { CGRect(x: $0.minX, y: (NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY) - $0.maxY, width: $0.width, height: $0.height).integral }
            self.complete(result)
        }
        chooser.contentView = view; panel = chooser
        NSApp.unhide(nil); chooser.makeKeyAndOrderFront(nil); chooser.makeFirstResponder(view)
    }
    func cancel() { complete(nil) }
    private func complete(_ rect: CGRect?) {
        let action = completion; completion = nil
        panel?.orderOut(nil); panel = nil
        action?(rect)
    }
}

private final class RegionSelectionView: NSView {
    var onSelect: ((NSRect?) -> Void)?
    private var start: NSPoint?
    private var selection = NSRect.zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill(); bounds.fill()
        NSColor.clear.setFill(); selection.fill(using: .copy)
        NSColor.white.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 2; path.stroke()
        ("Drag a region · Return for full display · Escape to cancel" as NSString).draw(at: NSPoint(x: 32, y: bounds.height - 60), withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7)])
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if selection.width >= 64, selection.height >= 64 { onSelect?(selection); onSelect = nil }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSelect?(nil); onSelect = nil }
        else if event.keyCode == 36 { onSelect?(bounds); onSelect = nil }
        else { super.keyDown(with: event) }
    }
}

private final class RegionSelectionPanel: NSPanel { override var canBecomeKey: Bool { true } }
