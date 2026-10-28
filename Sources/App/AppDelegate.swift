import AppKit
import SwiftUI
import Combine
import UserNotifications

public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    
    private static let kyivTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        return formatter
    }()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        setupMainMenu()
        setupStatusItem()
        observeManager()
        
        // Show desktop widget window on startup
        DesktopWidgetController.shared.showWindow(bringToFront: true)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DesktopWidgetController.shared.showWindow(bringToFront: true)
        completionHandler()
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App submenu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Про Yasno", action: #selector(openSettings), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Закрити Yasno", action: #selector(quitApp), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Standard Edit submenu (enables Cmd+V, Cmd+C, Cmd+X, Cmd+A, Cmd+Z in text fields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "yasnowidget" else { continue }
            switch url.host {
            case "switch-day":
                ScheduleManager.shared.toggleDayTab()
            case "switch-preset":
                ScheduleManager.shared.selectNextLocation()
            case "open":
                DesktopWidgetController.shared.showWindow(bringToFront: true)
            default:
                break
            }
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        updateStatusItemAppearance()
    }
    
    private func observeManager() {
        ScheduleManager.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        ScheduleManager.shared.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        ScheduleManager.shared.$selectedGroup
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        ScheduleManager.shared.$showMenuBarCountdown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        ScheduleManager.shared.$compactMenuBarMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        ScheduleManager.shared.$liveSensorStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        
        let manager = ScheduleManager.shared
        let status = manager.currentStatus
        let next = manager.nextEvent
        let showTimer = manager.showMenuBarCountdown
        let isCompact = manager.compactMenuBarMode
        
        let statusText: String
        var highlightImminent = false
        
        if manager.isEmergencyShutdown {
            statusText = isCompact ? "🚨 Аварія" : "🚨 Екстрені відключення"
            highlightImminent = true
        } else if status == .off {
            if case .turnsOn(_, let date) = next.eventType {
                let timeStr = Self.kyivTimeFormatter.string(from: date)
                let prefix = isCompact ? "🔴 \(timeStr)" : "🔴 Увімкнуть: \(timeStr)"
                if showTimer && next.minutesRemaining > 0 {
                    statusText = "\(prefix) (\(next.formattedShortCountdown))"
                } else {
                    statusText = prefix
                }
            } else if case .unplannedOutage(_, let date) = next.eventType {
                let timeStr = Self.kyivTimeFormatter.string(from: date)
                statusText = isCompact ? "🔴 Вимк" : "🔴 Поза графіком (до \(timeStr))"
            } else {
                statusText = isCompact ? "🔴 Вимк" : "🔴 Світла немає"
            }
        } else {
            if case .turnsOff(_, let date) = next.eventType {
                let timeStr = Self.kyivTimeFormatter.string(from: date)
                let imminent = next.isImminentTurnOff
                highlightImminent = imminent
                let dot = imminent ? "⚠️" : "🟢"
                let prefix = isCompact ? "\(dot) \(timeStr)" : "\(dot) Вимкнуть: \(timeStr)"
                if showTimer && next.minutesRemaining > 0 {
                    statusText = "\(prefix) (\(next.formattedShortCountdown))"
                } else {
                    statusText = prefix
                }
            } else {
                statusText = isCompact ? "🟢" : "🟢 Світло є"
            }
        }
        
        let fontSize: CGFloat = isCompact ? 12 : 13
        if highlightImminent {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
            ]
            button.attributedTitle = NSAttributedString(string: isCompact ? statusText : " \(statusText)", attributes: attrs)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: isCompact ? .semibold : .medium)
            ]
            button.attributedTitle = NSAttributedString(string: isCompact ? statusText : " \(statusText)", attributes: attrs)
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            DesktopWidgetController.shared.toggleWindow()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        let manager = ScheduleManager.shared
        
        // Status header
        let statusHeader = NSMenuItem(
            title: "\(manager.currentStatus.titleUk.uppercased()) • \(manager.selectedRegion.nameUk) (Черга \(manager.selectedGroup))",
            action: nil,
            keyEquivalent: ""
        )
        statusHeader.isEnabled = false
        menu.addItem(statusHeader)
        
        let nextEventItem = NSMenuItem(
            title: "\(manager.nextEvent.titleUk) (\(manager.nextEvent.subtitleUk))",
            action: nil,
            keyEquivalent: ""
        )
        nextEventItem.isEnabled = false
        menu.addItem(nextEventItem)
        
        if let sensor = manager.liveSensorStatus {
            let dot = sensor.state == .online ? "🟢" : (sensor.state == .offline ? "🔴" : "🟠")
            let sensorItem = NSMenuItem(
                title: "📡 \(dot) \(sensor.statusText)",
                action: nil,
                keyEquivalent: ""
            )
            sensorItem.isEnabled = false
            menu.addItem(sensorItem)
        }
        
        // Saved locations (presets) submenu / items
        if !manager.savedLocations.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let locTitle = NSMenuItem(title: "Збережені пресети:", action: nil, keyEquivalent: "")
            locTitle.isEnabled = false
            menu.addItem(locTitle)
            
            for (index, loc) in manager.savedLocations.enumerated() {
                let item = NSMenuItem(
                    title: "🏠 \(loc.name) (Черга \(loc.group))",
                    action: #selector(selectSavedLocationFromMenu(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                item.tag = index
                item.target = self
                if manager.activeLocation?.id == loc.id {
                    item.state = .on
                }
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(
            title: "Показати / Сховати віджет на екрані",
            action: #selector(toggleWidget),
            keyEquivalent: "w"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let pinItem = NSMenuItem(
            title: manager.isPinnedToDesktop ? "✓ Закріплено на робочому столі" : "Закріпити на робочому столі",
            action: #selector(togglePinToDesktop),
            keyEquivalent: "p"
        )
        pinItem.target = self
        menu.addItem(pinItem)
        
        let compactItem = NSMenuItem(
            title: manager.compactMenuBarMode ? "✓ Компактний вигляд у топбарі" : "Компактний вигляд у топбарі",
            action: #selector(toggleCompactMenuBar),
            keyEquivalent: "k"
        )
        compactItem.target = self
        menu.addItem(compactItem)
        
        let launchItem = NSMenuItem(
            title: manager.launchAtLogin ? "✓ Автозапуск при старті Mac" : "Автозапуск при старті Mac",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)
        
        let settingsItem = NSMenuItem(
            title: "Налаштування та пошук за адресою...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let refreshItem = NSMenuItem(
            title: "Оновити розклад",
            action: #selector(refreshSchedule),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Повністю закрити Yasno (Quit)",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }
    
    @objc private func selectSavedLocationFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        let locs = ScheduleManager.shared.savedLocations
        if index >= 0 && index < locs.count {
            ScheduleManager.shared.selectLocation(locs[index])
        }
    }
    
    @objc private func toggleWidget() {
        DesktopWidgetController.shared.toggleWindow()
    }
    
    @objc private func togglePinToDesktop() {
        ScheduleManager.shared.isPinnedToDesktop.toggle()
    }
    
    @objc private func toggleCompactMenuBar() {
        ScheduleManager.shared.compactMenuBarMode.toggle()
    }
    
    @objc private func toggleLaunchAtLogin() {
        ScheduleManager.shared.launchAtLogin.toggle()
    }
    
    @objc private func openSettings() {
        withAnimation(.easeInOut(duration: 0.18)) {
            ScheduleManager.shared.showSettings = true
        }
        DesktopWidgetController.shared.showWindow(bringToFront: true)
    }
    
    @objc private func refreshSchedule() {
        ScheduleManager.shared.refresh()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
