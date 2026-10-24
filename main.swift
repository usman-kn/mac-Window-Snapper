// Snapper — a tiny window snapping app for macOS.
// Keyboard shortcuts (⌃⌥ + key) and drag-to-screen-edge snapping.

import Cocoa
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Coordinates
// Accessibility uses a top-left origin (relative to the primary screen);
// Cocoa uses bottom-left. The flip is its own inverse.

func flip(_ r: CGRect) -> CGRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

func flip(_ p: CGPoint) -> CGPoint {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGPoint(x: p.x, y: h - p.y)
}

extension CGRect {
    var integral2: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }
    func approx(_ o: CGRect, _ tol: CGFloat = 12) -> Bool {
        abs(minX - o.minX) < tol && abs(minY - o.minY) < tol &&
        abs(width - o.width) < tol && abs(height - o.height) < tol
    }
    var area: CGFloat { isNull ? 0 : width * height }
}

// MARK: - Accessibility window wrapper

struct AXWindow {
    let element: AXUIElement

    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return AXWindow(element: ref as! AXUIElement)
    }

    /// Window under a point given in AX (top-left) coordinates.
    static func at(_ p: CGPoint) -> AXWindow? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              var el = hit else { return nil }
        for _ in 0..<25 {
            if role(of: el) == kAXWindowRole { return AXWindow(element: el) }
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &ref) == .success,
               let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
                return AXWindow(element: ref as! AXUIElement)
            }
            guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &ref) == .success,
                  let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
            el = ref as! AXUIElement
        }
        return nil
    }

    private static func role(of el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &ref)
        return ref as? String
    }

    private func axValue(_ attr: String) -> AXValue? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }

    /// Frame in AX (top-left) coordinates.
    var frame: CGRect? {
        var p = CGPoint.zero, s = CGSize.zero
        guard let pv = axValue(kAXPositionAttribute), AXValueGetValue(pv, .cgPoint, &p),
              let sv = axValue(kAXSizeAttribute), AXValueGetValue(sv, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Frame in Cocoa (bottom-left) coordinates.
    var cocoaFrame: CGRect? { frame.map(flip) }

    func setCocoaFrame(_ r: CGRect) {
        let ax = flip(r.integral2)
        var pos = ax.origin, size = ax.size
        guard let pv = AXValueCreate(.cgPoint, &pos), let sv = AXValueCreate(.cgSize, &size) else { return }
        // Position → size → position: survives moves between displays of different sizes.
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pv)
    }

    func isSame(_ o: AXWindow) -> Bool { CFEqual(element, o.element) }
}

// MARK: - Actions

enum Action: CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case maximize, center
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case previousDisplay, nextDisplay
    case restore

    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .maximize: "Maximize"
        case .center: "Center"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First Two Thirds"
        case .lastTwoThirds: "Last Two Thirds"
        case .previousDisplay: "Previous Display"
        case .nextDisplay: "Next Display"
        case .restore: "Restore"
        }
    }

    /// Carbon virtual key code.
    var keyCode: Int {
        switch self {
        case .leftHalf, .previousDisplay: kVK_LeftArrow
        case .rightHalf, .nextDisplay: kVK_RightArrow
        case .topHalf: kVK_UpArrow
        case .bottomHalf: kVK_DownArrow
        case .maximize: kVK_Return
        case .center: kVK_ANSI_C
        case .topLeft: kVK_ANSI_U
        case .topRight: kVK_ANSI_I
        case .bottomLeft: kVK_ANSI_J
        case .bottomRight: kVK_ANSI_K
        case .firstThird: kVK_ANSI_D
        case .centerThird: kVK_ANSI_F
        case .lastThird: kVK_ANSI_G
        case .firstTwoThirds: kVK_ANSI_E
        case .lastTwoThirds: kVK_ANSI_T
        case .restore: kVK_Delete
        }
    }

    var carbonModifiers: Int {
        switch self {
        case .previousDisplay, .nextDisplay: controlKey | optionKey | cmdKey
        default: controlKey | optionKey
        }
    }

    var menuKey: String {
        func fn(_ k: Int) -> String { String(Character(UnicodeScalar(k)!)) }
        switch keyCode {
        case kVK_LeftArrow: return fn(NSLeftArrowFunctionKey)
        case kVK_RightArrow: return fn(NSRightArrowFunctionKey)
        case kVK_UpArrow: return fn(NSUpArrowFunctionKey)
        case kVK_DownArrow: return fn(NSDownArrowFunctionKey)
        case kVK_Return: return "\r"
        case kVK_Delete: return "\u{8}"
        default:
            let map = [kVK_ANSI_C: "c", kVK_ANSI_U: "u", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k",
                       kVK_ANSI_D: "d", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_E: "e", kVK_ANSI_T: "t"]
            return map[keyCode] ?? ""
        }
    }

    var menuModifiers: NSEvent.ModifierFlags {
        carbonModifiers & cmdKey != 0 ? [.control, .option, .command] : [.control, .option]
    }

    /// Target rect(s) in Cocoa coordinates within a screen's visible frame.
    /// Halves return several candidates; repeating the shortcut cycles ½ → ⅔ → ⅓.
    func candidates(in v: CGRect, current: CGRect) -> [CGRect] {
        let w = v.width, h = v.height
        let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
        switch self {
        case .leftHalf:
            return fractions.map { CGRect(x: v.minX, y: v.minY, width: w * $0, height: h) }
        case .rightHalf:
            return fractions.map { CGRect(x: v.maxX - w * $0, y: v.minY, width: w * $0, height: h) }
        case .topHalf:
            return fractions.map { CGRect(x: v.minX, y: v.maxY - h * $0, width: w, height: h * $0) }
        case .bottomHalf:
            return fractions.map { CGRect(x: v.minX, y: v.minY, width: w, height: h * $0) }
        case .maximize: return [v]
        case .center:
            let cw = min(current.width, w), ch = min(current.height, h)
            return [CGRect(x: v.midX - cw / 2, y: v.midY - ch / 2, width: cw, height: ch)]
        case .topLeft: return [CGRect(x: v.minX, y: v.midY, width: w / 2, height: h / 2)]
        case .topRight: return [CGRect(x: v.midX, y: v.midY, width: w / 2, height: h / 2)]
        case .bottomLeft: return [CGRect(x: v.minX, y: v.minY, width: w / 2, height: h / 2)]
        case .bottomRight: return [CGRect(x: v.midX, y: v.minY, width: w / 2, height: h / 2)]
        case .firstThird: return [CGRect(x: v.minX, y: v.minY, width: w / 3, height: h)]
        case .centerThird: return [CGRect(x: v.minX + w / 3, y: v.minY, width: w / 3, height: h)]
        case .lastThird: return [CGRect(x: v.maxX - w / 3, y: v.minY, width: w / 3, height: h)]
        case .firstTwoThirds: return [CGRect(x: v.minX, y: v.minY, width: w * 2 / 3, height: h)]
        case .lastTwoThirds: return [CGRect(x: v.maxX - w * 2 / 3, y: v.minY, width: w * 2 / 3, height: h)]
        case .previousDisplay, .nextDisplay, .restore: return []
        }
    }
}

// MARK: - Window manager

enum WindowManager {
    /// Pre-snap frames so ⌃⌥⌫ can restore them.
    private static var history: [(AXWindow, CGRect)] = []

    static func screen(for r: CGRect) -> NSScreen? {
        NSScreen.screens.max { $0.frame.intersection(r).area < $1.frame.intersection(r).area } ?? NSScreen.main
    }

    static func perform(_ action: Action) {
        guard AXIsProcessTrusted() else { AppDelegate.promptForAccess(); return }
        guard let win = AXWindow.focused() else { NSSound.beep(); return }
        perform(action, on: win)
    }

    static func perform(_ action: Action, on win: AXWindow, screen forcedScreen: NSScreen? = nil) {
        guard let current = win.cocoaFrame,
              let screen = forcedScreen ?? screen(for: current) else { return }

        switch action {
        case .restore:
            if let i = history.lastIndex(where: { $0.0.isSame(win) }) {
                win.setCocoaFrame(history.remove(at: i).1)
            }
            return
        case .previousDisplay, .nextDisplay:
            let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            guard screens.count > 1, let i = screens.firstIndex(of: screen) else { return }
            let target = screens[(i + (action == .nextDisplay ? 1 : -1) + screens.count) % screens.count]
            let a = screen.visibleFrame, b = target.visibleFrame
            let sx = b.width / a.width, sy = b.height / a.height
            var r = CGRect(x: b.minX + (current.minX - a.minX) * sx, y: b.minY + (current.minY - a.minY) * sy,
                           width: current.width * sx, height: current.height * sy)
            r = r.intersection(b).isNull ? b : r.intersection(b)
            win.setCocoaFrame(r)
            return
        default:
            break
        }

        let options = action.candidates(in: screen.visibleFrame, current: current)
        guard !options.isEmpty else { return }
        // Cycle if the window already sits in one of this action's positions.
        var next = 0
        if let i = options.firstIndex(where: { $0.approx(current) }) {
            next = (i + 1) % options.count
        } else {
            remember(win, current)
        }
        win.setCocoaFrame(options[next])
    }

    static func remember(_ win: AXWindow, _ frame: CGRect) {
        history.removeAll { $0.0.isSame(win) }
        history.append((win, frame))
        if history.count > 100 { history.removeFirst() }
    }
}

// MARK: - Global hotkeys (Carbon — no extra permission needed to listen)

enum HotKeys {
    static var actions: [UInt32: Action] = [:]
    static var refs: [EventHotKeyRef] = []

    static func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = HotKeys.actions[id.id] { WindowManager.perform(action) }
            return noErr
        }, 1, &spec, nil, nil)

        for action in Action.allCases {
            let id = UInt32(actions.count + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(action.keyCode), UInt32(action.carbonModifiers),
                                             EventHotKeyID(signature: OSType(0x534E_4150), id: id), // 'SNAP'
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                actions[id] = action
                refs.append(ref)
            } else {
                NSLog("Snapper: could not register shortcut for \(action.title) (taken by another app?)")
            }
        }
    }
}

// MARK: - Drag to edge

final class Overlay {
    private let window: NSWindow

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 2
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        window.contentView = view
    }

    func show(_ r: CGRect) {
        let target = r.insetBy(dx: 6, dy: 6)
        if window.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
            window.alphaValue = 1
            window.orderFrontRegardless()
        }
    }

    func hide() { window.orderOut(nil) }
}

final class DragSnapper {
    static let enabledKey = "dragSnappingEnabled"
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    private let overlay = Overlay()
    private var window: AXWindow?
    private var startFrame: CGRect?
    private var probes = 0
    private var moving = false
    private var zone: (Action, NSScreen)?

    private let edge: CGFloat = 5       // how close to the edge the cursor must be
    private let corner: CGFloat = 140   // corner hot-zone size along each edge

    func start() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
            self?.handle(e)
        }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            reset()
            guard enabled, AXIsProcessTrusted() else { return }
            if let w = AXWindow.at(flip(NSEvent.mouseLocation)), let f = w.frame {
                window = w
                startFrame = f
            }
        case .leftMouseDragged:
            guard let w = window, let start = startFrame else { return }
            if !moving {
                // Confirm the window is being moved (not resized, not a text selection).
                probes += 1
                guard probes < 40, let f = w.frame else { window = nil; return }
                if f.size != start.size { window = nil; return }
                if f.origin == start.origin { return }
                moving = true
            }
            updateZone()
        case .leftMouseUp:
            if moving, let (action, screen) = zone, let w = window, let original = startFrame {
                let restoreFrame = flip(original)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    WindowManager.remember(w, restoreFrame)
                    let current = w.cocoaFrame ?? restoreFrame
                    if let r = action.candidates(in: screen.visibleFrame, current: current).first {
                        w.setCocoaFrame(r)
                    }
                }
            }
            reset()
        default:
            break
        }
    }

    private func updateZone() {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }) else { return }
        let f = screen.frame
        let atLeft = p.x <= f.minX + edge, atRight = p.x >= f.maxX - edge
        let atTop = p.y >= f.maxY - edge, atBottom = p.y <= f.minY + edge
        let nearLeft = p.x <= f.minX + corner, nearRight = p.x >= f.maxX - corner
        let nearTop = p.y >= f.maxY - corner, nearBottom = p.y <= f.minY + corner

        var action: Action?
        if (atLeft && nearTop) || (atTop && nearLeft) { action = .topLeft }
        else if (atRight && nearTop) || (atTop && nearRight) { action = .topRight }
        else if (atLeft && nearBottom) || (atBottom && nearLeft) { action = .bottomLeft }
        else if (atRight && nearBottom) || (atBottom && nearRight) { action = .bottomRight }
        else if atLeft { action = .leftHalf }
        else if atRight { action = .rightHalf }
        else if atTop { action = .maximize }

        guard let action else {
            if zone != nil { zone = nil; overlay.hide() }
            return
        }
        if zone?.0 == action && zone?.1 == screen { return }
        zone = (action, screen)
        let current = window?.cocoaFrame ?? screen.visibleFrame
        if let r = action.candidates(in: screen.visibleFrame, current: current).first { overlay.show(r) }
    }

    private func reset() {
        window = nil
        startFrame = nil
        probes = 0
        moving = false
        zone = nil
        overlay.hide()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let drag = DragSnapper()
    private var accessItem: NSMenuItem!
    private var dragItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    static func promptForAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        if !AXIsProcessTrusted() { Self.promptForAccess() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Snapper")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = buildMenu()

        HotKeys.install()
        drag.start()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        accessItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openAccess), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)

        let groups: [[Action]] = [
            [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
            [.topLeft, .topRight, .bottomLeft, .bottomRight],
            [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
            [.maximize, .center, .restore],
            [.previousDisplay, .nextDisplay],
        ]
        for group in groups {
            menu.addItem(.separator())
            for action in group {
                let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: action.menuKey)
                item.keyEquivalentModifierMask = action.menuModifiers
                item.representedObject = action
                item.target = self
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        dragItem = NSMenuItem(title: "Snap When Dragging to Screen Edges", action: #selector(toggleDrag), keyEquivalent: "")
        dragItem.target = self
        menu.addItem(dragItem)
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Snapper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        accessItem.isHidden = AXIsProcessTrusted()
        dragItem.state = drag.enabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? Action else { return }
        WindowManager.perform(action)
    }

    @objc private func openAccess() {
        Self.promptForAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleDrag() { drag.enabled.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
