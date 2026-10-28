import AppKit
import SwiftUI

public final class DesktopWidgetController: NSObject, NSWindowDelegate {
    public static let shared = DesktopWidgetController()
    
    private var window: NSPanel?
    private let windowPosKey = "yasno_desktop_widget_position"
    
    /// Above Finder's desktop icon click-catcher, below normal app windows
    private var desktopWidgetLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    
    public override init() {
        super.init()
    }
    
    public func showWindow(bringToFront: Bool = false) {
        if window == nil {
            setupWindow()
        }
        guard let win = window else { return }
        ensureWindowOnVisibleScreen(win)
        
        if bringToFront || ScheduleManager.shared.showSettings || !ScheduleManager.shared.isPinnedToDesktop {
            win.level = .floating
        } else {
            win.level = desktopWidgetLevel
        }
        
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }
    
    public func hideWindow() {
        window?.orderOut(nil)
    }
    
    public func toggleWindow() {
        if let win = window, win.isVisible {
            if win.level != .floating || !win.isKeyWindow {
                showWindow(bringToFront: true)
            } else {
                hideWindow()
            }
        } else {
            showWindow(bringToFront: true)
        }
    }
    
    public func updateWindowLevel(isPinnedToDesktop: Bool) {
        guard let win = window else { return }
        if isPinnedToDesktop && !ScheduleManager.shared.showSettings {
            win.level = desktopWidgetLevel
        } else {
            win.level = .floating
            win.orderFrontRegardless()
        }
    }
    
    public func updateForSettingsState(showSettings: Bool) {
        guard let win = window else { return }
        if showSettings {
            win.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
        } else {
            win.level = ScheduleManager.shared.isPinnedToDesktop ? desktopWidgetLevel : .floating
        }
        DispatchQueue.main.async {
            win.contentView?.needsLayout = true
            win.contentView?.layoutSubtreeIfNeeded()
            win.contentView?.needsDisplay = true
            win.invalidateShadow()
        }
    }
    
    private func activeScreen() -> NSScreen? {
        let mouseLoc = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
    
    private func ensureWindowOnVisibleScreen(_ panel: NSPanel) {
        let currentOrigin = panel.frame.origin
        let isOnAnyScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(NSRect(x: currentOrigin.x, y: currentOrigin.y, width: 100, height: 100))
        }
        if !isOnAnyScreen, let screen = activeScreen() {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 388
            let y = screenFrame.maxY - 540
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    private func setupWindow() {
        let isPinned = ScheduleManager.shared.isPinnedToDesktop
        let panel = CustomWidgetPanel(
            contentRect: NSRect(x: 100, y: 100, width: 368, height: 520),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = false
        panel.level = isPinned ? desktopWidgetLevel : .floating
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self
        
        let hostingView = TransparentHostingView(rootView: DesktopWidgetView(manager: ScheduleManager.shared))
        panel.contentView = hostingView
        
        // Restore previous position or position in top-right of active screen
        if let savedPos = UserDefaults.standard.string(forKey: windowPosKey) {
            let point = NSPointFromString(savedPos)
            panel.setFrameOrigin(point)
            ensureWindowOnVisibleScreen(panel)
        } else if let screen = activeScreen() {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 388
            let y = screenFrame.maxY - 540
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.window = panel
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    
    public func windowDidMove(_ notification: Notification) {
        if let win = window {
            let posString = NSStringFromPoint(win.frame.origin)
            UserDefaults.standard.set(posString, forKey: windowPosKey)
        }
    }
}

// Transparent NSHostingView that never swallows button clicks as window drags
fileprivate final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// Subclass that activates immediately on click and supports smooth dragging without interfering with Settings controls/scrolling
fileprivate final class CustomWidgetPanel: NSPanel {
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var isDraggingWindow = false
    private var canDragOnCurrentClick = false
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !self.isKeyWindow {
                self.makeKey()
            }
            
            // In Settings mode, only allow window dragging from the top header bar (top 65pt),
            // so scrolling, text selection, and dropdown pickers work with zero interference!
            let locInWindow = event.locationInWindow
            if ScheduleManager.shared.showSettings {
                canDragOnCurrentClick = locInWindow.y > (self.frame.height - 65)
            } else {
                canDragOnCurrentClick = true
            }
            
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = self.frame.origin
            isDraggingWindow = false
            super.sendEvent(event)
            
        case .leftMouseDragged:
            if canDragOnCurrentClick,
               let startMouse = dragStartMouseLocation,
               let startOrigin = dragStartWindowOrigin {
                let currentMouse = NSEvent.mouseLocation
                let dx = currentMouse.x - startMouse.x
                let dy = currentMouse.y - startMouse.y
                if isDraggingWindow || hypot(dx, dy) > 6.0 {
                    isDraggingWindow = true
                    self.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
                    return
                }
            }
            super.sendEvent(event)
            
        case .leftMouseUp:
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            isDraggingWindow = false
            canDragOnCurrentClick = false
            super.sendEvent(event)
            
        default:
            super.sendEvent(event)
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            switch key {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                    return true
                }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                    return true
                }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                    return true
                }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) {
                    return true
                }
            case "z":
                let action = event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
                if NSApp.sendAction(action, to: nil, from: self) {
                    return true
                }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func cancelOperation(_ sender: Any?) {
        if ScheduleManager.shared.showSettings {
            ScheduleManager.shared.showSettings = false
        } else {
            self.orderOut(nil)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // Don't hijack arrow keys when user is typing in Settings text fields!
        guard !ScheduleManager.shared.showSettings else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 53: // ESC key
            self.orderOut(nil)
        case 123, 124: // Left Arrow (123) or Right Arrow (124)
            ScheduleManager.shared.toggleDayTab()
        default:
            super.keyDown(with: event)
        }
    }
}
