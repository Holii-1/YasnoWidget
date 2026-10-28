import Foundation
import AppKit
import SwiftUI
import Combine
import UserNotifications
import WidgetKit
import ServiceManagement

public final class ScheduleManager: ObservableObject {
    public static let shared = ScheduleManager()
    
    // User preferences keys
    private let prefRegionKey = "yasno_pref_region_id"
    private let prefGroupKey = "yasno_pref_group"
    private let prefNotificationsKey = "yasno_pref_notifications_enabled"
    private let prefPinnedToDesktopKey = "yasno_pref_pinned_to_desktop"
    private let prefLocationsKey = "yasno_pref_saved_locations"
    private let prefActiveLocationIdKey = "yasno_pref_active_location_id"
    private let prefMenuBarCountdownKey = "yasno_pref_menubar_countdown"
    private let prefCompactMenuBarKey = "yasno_pref_compact_menubar"
    private let prefLaunchAtLoginKey = "yasno_pref_launch_at_login"
    
    // Published properties
    @Published public var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: prefLaunchAtLoginKey)
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }
    
    @Published public var compactMenuBarMode: Bool {
        didSet {
            UserDefaults.standard.set(compactMenuBarMode, forKey: prefCompactMenuBarKey)
        }
    }
    
    @Published public var isPinnedToDesktop: Bool {
        didSet {
            UserDefaults.standard.set(isPinnedToDesktop, forKey: prefPinnedToDesktopKey)
            DesktopWidgetController.shared.updateWindowLevel(isPinnedToDesktop: isPinnedToDesktop)
        }
    }
    
    @Published public var showMenuBarCountdown: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarCountdown, forKey: prefMenuBarCountdownKey)
        }
    }
    
    @Published public var selectedRegion: YasnoRegion {
        didSet {
            UserDefaults.standard.set(selectedRegion.id, forKey: prefRegionKey)
            syncSharedState()
            refresh()
        }
    }
    
    @Published public private(set) var selectedGroup: String {
        didSet {
            UserDefaults.standard.set(selectedGroup, forKey: prefGroupKey)
            syncSharedState()
            refresh()
        }
    }
    
    @Published public var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: prefNotificationsKey)
            if notificationsEnabled {
                requestNotificationPermission()
            }
        }
    }
    
    // Saved Locations (Bookmarks / Presets)
    @Published public private(set) var savedLocations: [SavedLocation] {
        didSet {
            if let data = try? JSONEncoder().encode(savedLocations) {
                UserDefaults.standard.set(data, forKey: prefLocationsKey)
            }
            syncSharedState()
        }
    }
    
    @Published public private(set) var activeLocationId: String? {
        didSet {
            UserDefaults.standard.set(activeLocationId, forKey: prefActiveLocationIdKey)
            syncSharedState()
        }
    }
    
    @Published public private(set) var snapshot: ScheduleSnapshot?
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var currentTime: Date = Date()
    
    // UI presentation states
    @Published public var selectedTab: Int = 0 {
        didSet {
            syncSharedState()
        }
    }
    @Published public var isExpanded: Bool = true
    @Published public var showSettings: Bool = false {
        didSet {
            DesktopWidgetController.shared.updateForSettingsState(showSettings: showSettings)
        }
    }
    
    // New Preset Form state
    @Published public var newLocationName: String = ""
    @Published public var newLocationGroup: String = "1.1"
    
    // Edit Preset Form state
    @Published public var editingLocationId: String? = nil
    @Published public var editingLocationName: String = ""
    @Published public var editingLocationGroup: String = "1.1"
    
    // Live Sensor (SvitloBot / Healthchecks.io) state
    @Published public private(set) var liveSensorStatus: LiveSensorStatus?
    @Published public private(set) var isCheckingSensor: Bool = false
    @Published public var sensorInputType: LiveSensorType = .disabled
    @Published public var sensorInputTarget: String = ""
    @Published public var detectedGroupFromSensor: String? = nil
    @Published public var autoDetectedGroupNotice: String? = nil
    private var shouldAutoApplySensorGroup: Bool = false
    private var notifiedOutageKeys: Set<String> = []
    private let prefNotifiedOutageKeys = "yasno_pref_notified_outage_keys"
    private let prefLastSensorStatesKey = "yasno_pref_last_sensor_states"
    private var sensorCheckTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastWidgetFingerprint: String?
    private var lastGoodSensorStatus: LiveSensorStatus?
    private var lastKnownSensorStateByLocation: [String: LivePowerState] = [:]
    private var localTransitionsByLocation: [String: [PowerTransitionEvent]] = [:]
    private let prefLocalTransitionsKey = "yasno_pref_local_sensor_transitions"
    
    // Address Lookup state
    @Published public var streetQuery: String = ""
    @Published public private(set) var streetResults: [YasnoAddressItem] = []
    @Published public private(set) var selectedStreet: YasnoAddressItem?
    @Published public var houseQuery: String = ""
    @Published public private(set) var houseResults: [YasnoAddressItem] = []
    @Published public private(set) var selectedHouse: YasnoAddressItem?
    @Published public private(set) var resolvedAddressGroup: String?
    @Published public private(set) var addressSearchError: String?
    @Published public private(set) var isSearchingAddress: Bool = false
    
    private var streetSearchTask: Task<Void, Never>?
    private var houseSearchTask: Task<Void, Never>?
    
    public var isEmergencyShutdown: Bool {
        alignedDays.today?.status == .emergencyShutdowns
    }
    
    /// Today / tomorrow aligned to the real Kyiv calendar day (protects from showing yesterday's cache after midnight)
    public var alignedDays: (today: DaySchedule?, tomorrow: DaySchedule?) {
        snapshot?.alignedDays(for: currentTime) ?? (nil, nil)
    }
    
    /// True when the displayed schedule comes from an old cache because Yasno is unreachable
    public var isShowingStaleData: Bool {
        guard let snap = snapshot else { return false }
        return lastError != nil && currentTime.timeIntervalSince(snap.lastUpdated) > 30 * 60
    }
    
    public var activeLocation: SavedLocation? {
        if let id = activeLocationId, let match = savedLocations.first(where: { $0.id == id }) {
            return match
        }
        return savedLocations.first(where: { $0.group == selectedGroup && $0.regionId == selectedRegion.id })
    }
    
    public var allAvailableGroups: [String] {
        var groups = Set(selectedRegion.availableGroups)
        if let discovered = snapshot?.discoveredGroups, !discovered.isEmpty {
            for g in discovered {
                groups.insert(g)
            }
        }
        for loc in savedLocations {
            groups.insert(loc.group)
        }
        groups.insert(selectedGroup)
        if let resolved = resolvedAddressGroup {
            groups.insert(resolved)
        }
        return groups.sorted { a, b in
            a.localizedStandardCompare(b) == .orderedAscending
        }
    }
    
    // MARK: - Group & Preset Selection
    public func setGroup(_ group: String, updateActivePreset: Bool = false) {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if updateActivePreset, let activeId = activeLocationId,
           let idx = savedLocations.firstIndex(where: { $0.id == activeId }) {
            if savedLocations[idx].group != trimmed {
                savedLocations[idx].group = trimmed
            }
            if self.selectedGroup != trimmed {
                self.selectedGroup = trimmed
            }
            return
        }
        
        let previousLocationId = self.activeLocationId
        if let matchingLoc = savedLocations.first(where: { $0.group == trimmed && $0.regionId == selectedRegion.id }) {
            self.activeLocationId = matchingLoc.id
        } else {
            self.activeLocationId = nil
        }
        if previousLocationId != self.activeLocationId {
            sensorCheckTask?.cancel()
            liveSensorStatus = nil
            lastGoodSensorStatus = nil
        }
        if self.selectedGroup != trimmed {
            self.selectedGroup = trimmed
        }
    }
    
    public func selectLocation(_ location: SavedLocation) {
        let isDifferentLocation = (self.activeLocationId != location.id)
        self.activeLocationId = location.id
        if isDifferentLocation {
            // Never apply the previous preset's sensor state to the new preset's schedule
            sensorCheckTask?.cancel()
            liveSensorStatus = nil
            lastGoodSensorStatus = nil
            detectedGroupFromSensor = nil
            autoDetectedGroupNotice = nil
        }
        if let region = YasnoRegion.all.first(where: { $0.id == location.regionId }) {
            if self.selectedRegion != region {
                self.selectedRegion = region
            }
        }
        if self.selectedGroup != location.group {
            self.selectedGroup = location.group
        }
        syncSensorInputsFromActiveLocation()
        refreshLiveSensor()
    }
    
    public func syncSensorInputsFromActiveLocation() {
        if let loc = activeLocation {
            sensorInputType = loc.sensorType
            sensorInputTarget = loc.sensorTarget ?? ""
        } else {
            sensorInputType = .disabled
            sensorInputTarget = ""
        }
    }
    
    public func setSensorTypeForActiveLocation(_ type: LiveSensorType) {
        sensorInputType = type
        if type == .disabled {
            saveSensorConfigForActiveLocation(type: .disabled, target: "")
        } else if !sensorInputTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveSensorConfigForActiveLocation(type: type, target: sensorInputTarget)
        }
    }
    
    public func saveSensorConfigForActiveLocation(type: LiveSensorType, target: String) {
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        sensorInputType = type
        sensorInputTarget = cleanTarget
        detectedGroupFromSensor = nil
        autoDetectedGroupNotice = nil
        shouldAutoApplySensorGroup = true
        
        if let activeId = activeLocation?.id,
           let idx = savedLocations.firstIndex(where: { $0.id == activeId }) {
            savedLocations[idx].sensorType = type
            savedLocations[idx].sensorTarget = cleanTarget.isEmpty ? nil : cleanTarget
        } else if !savedLocations.isEmpty {
            savedLocations[0].sensorType = type
            savedLocations[0].sensorTarget = cleanTarget.isEmpty ? nil : cleanTarget
            activeLocationId = savedLocations[0].id
        }
        
        if type == .disabled || cleanTarget.isEmpty {
            sensorCheckTask?.cancel()
            isCheckingSensor = false
            liveSensorStatus = nil
            syncSharedState()
        } else {
            refreshLiveSensor()
        }
    }
    
    public func refreshLiveSensor() {
        sensorCheckTask?.cancel()
        guard let loc = activeLocation,
              loc.sensorType != .disabled,
              let target = loc.sensorTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty else {
            isCheckingSensor = false
            liveSensorStatus = nil
            syncSharedState()
            return
        }
        
        isCheckingSensor = true
        let locId = loc.id
        let locName = loc.name
        let sensorType = loc.sensorType
        
        sensorCheckTask = Task { @MainActor in
            let result = await LiveMonitorService.shared.checkStatus(type: sensorType, target: target)
            guard !Task.isCancelled, self.activeLocation?.id == locId else { return }
            self.isCheckingSensor = false
            
            if var newStatus = result {
                // If group is not explicitly in text or slug, infer it using APIService ONLY if not yet set or just configured
                let needsGroupInference = (loc.group == "1.1" || self.shouldAutoApplySensorGroup)
                if needsGroupInference && (newStatus.detectedGroup == nil || newStatus.detectedGroup?.isEmpty == true) {
                    if let inferred = await YasnoAPIService.shared.inferGroupFromSensor(region: self.selectedRegion, status: newStatus) {
                        newStatus = LiveSensorStatus(
                            source: newStatus.source,
                            state: newStatus.state,
                            statusText: newStatus.statusText,
                            detailText: newStatus.detailText,
                            eventTimestamp: newStatus.eventTimestamp,
                            checkedAt: newStatus.checkedAt,
                            transitions: newStatus.transitions,
                            detectedGroup: inferred,
                            channelTitle: newStatus.channelTitle,
                            plannedHints: newStatus.plannedHints
                        )
                    }
                }
                
                // A single failed poll (network hiccup / Telegram timeout) must not flip the whole timeline
                // back to the planned schedule every 30 seconds. Keep the last good reading for up to 3 minutes.
                if newStatus.state == .error || newStatus.state == .unknown,
                   let lastGood = self.lastGoodSensorStatus,
                   Date().timeIntervalSince(lastGood.checkedAt) < 180 {
                    self.liveSensorStatus = lastGood
                    self.syncSharedState()
                    return
                }
                
                let prevState = self.lastKnownSensorStateByLocation[locId]
                if newStatus.state == .online || newStatus.state == .offline {
                    if let prev = prevState, prev != newStatus.state {
                        self.sendLivePowerChangeNotification(locationName: locName, newStatus: newStatus)
                        let evt = PowerTransitionEvent(
                            timestamp: newStatus.eventTimestamp ?? Date(),
                            isPowerOn: newStatus.state == .online
                        )
                        var history = (self.localTransitionsByLocation[locId] ?? []).filter {
                            Date().timeIntervalSince($0.timestamp) < 172800
                        }
                        history.append(evt)
                        self.localTransitionsByLocation[locId] = history
                        if let encoded = try? JSONEncoder().encode(self.localTransitionsByLocation) {
                            UserDefaults.standard.set(encoded, forKey: self.prefLocalTransitionsKey)
                        }
                    }
                    self.lastKnownSensorStateByLocation[locId] = newStatus.state
                    if let encodedStates = try? JSONEncoder().encode(self.lastKnownSensorStateByLocation) {
                        UserDefaults.standard.set(encodedStates, forKey: self.prefLastSensorStatesKey)
                    }
                }
                
                // If server didn't provide transition history (e.g. Badge URL), attach locally recorded transitions
                if newStatus.transitions.isEmpty,
                   let localHistory = self.localTransitionsByLocation[locId],
                   !localHistory.isEmpty {
                    newStatus = LiveSensorStatus(
                        source: newStatus.source,
                        state: newStatus.state,
                        statusText: newStatus.statusText,
                        detailText: newStatus.detailText,
                        eventTimestamp: newStatus.eventTimestamp,
                        checkedAt: newStatus.checkedAt,
                        transitions: localHistory,
                        detectedGroup: newStatus.detectedGroup,
                        channelTitle: newStatus.channelTitle,
                        plannedHints: newStatus.plannedHints
                    )
                }
                self.liveSensorStatus = newStatus
                if newStatus.state == .online || newStatus.state == .offline {
                    self.lastGoodSensorStatus = newStatus
                }
                
                // Auto-detect group from SvitloBot / Healthchecks if available
                if let detected = newStatus.detectedGroup, !detected.isEmpty {
                    self.handleDetectedGroup(detected, forLocationId: locId)
                }
            } else {
                self.liveSensorStatus = nil
            }
            
            self.syncSharedState()
        }
    }
    
    // MARK: - Sensor Group Auto-Detection & Handling
    public func handleDetectedGroup(_ detected: String, forLocationId: String) {
        guard let loc = savedLocations.first(where: { $0.id == forLocationId }) else { return }
        
        let normalizedGroup: String
        if allAvailableGroups.contains(detected) {
            normalizedGroup = detected
        } else if let resolved = allAvailableGroups.first(where: { $0.hasPrefix(detected + ".") }) {
            normalizedGroup = resolved
        } else {
            normalizedGroup = detected
        }
        
        // If current group of this preset is already equal to detected, nothing to do!
        if loc.group == normalizedGroup {
            self.detectedGroupFromSensor = nil
            self.shouldAutoApplySensorGroup = false
            return
        }
        
        if shouldAutoApplySensorGroup || loc.group == "1.1" {
            self.setGroup(normalizedGroup, updateActivePreset: true)
            self.shouldAutoApplySensorGroup = false
            self.autoDetectedGroupNotice = "Чергу \(normalizedGroup) автоматично підтягнуто з каналу датчика"
            self.detectedGroupFromSensor = nil
        } else {
            // Preset already has a custom group manually set: offer 1-click button
            self.detectedGroupFromSensor = normalizedGroup
            self.autoDetectedGroupNotice = nil
        }
    }
    
    public func applyDetectedGroup() {
        guard let detected = detectedGroupFromSensor else { return }
        self.setGroup(detected, updateActivePreset: true)
        self.autoDetectedGroupNotice = "Чергу \(detected) успішно застосовано"
        self.detectedGroupFromSensor = nil
    }
    
    public func selectNextLocation() {
        guard !savedLocations.isEmpty else { return }
        if let currentId = activeLocation?.id,
           let idx = savedLocations.firstIndex(where: { $0.id == currentId }) {
            let nextIdx = (idx + 1) % savedLocations.count
            selectLocation(savedLocations[nextIdx])
        } else {
            selectLocation(savedLocations[0])
        }
    }
    
    public func selectPreviousLocation() {
        guard !savedLocations.isEmpty else { return }
        if let currentId = activeLocation?.id,
           let idx = savedLocations.firstIndex(where: { $0.id == currentId }) {
            let prevIdx = (idx - 1 + savedLocations.count) % savedLocations.count
            selectLocation(savedLocations[prevIdx])
        } else {
            selectLocation(savedLocations[0])
        }
    }
    
    // MARK: - Add / Edit / Remove Presets
    public func addSavedLocation(name: String, group: String, addressNote: String? = nil) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanGroup.isEmpty else { return }
        
        let newLoc = SavedLocation(
            name: cleanName,
            regionId: selectedRegion.id,
            dsoId: selectedRegion.dsoId,
            group: cleanGroup,
            addressNote: addressNote
        )
        savedLocations.append(newLoc)
        selectLocation(newLoc)
        newLocationName = ""
    }
    
    public func startEditingLocation(_ location: SavedLocation) {
        editingLocationId = location.id
        editingLocationName = location.name
        editingLocationGroup = location.group
    }
    
    public func cancelEditingLocation() {
        editingLocationId = nil
        editingLocationName = ""
    }
    
    public func saveEditedLocation() {
        guard let editId = editingLocationId,
              let idx = savedLocations.firstIndex(where: { $0.id == editId }) else {
            return
        }
        let cleanName = editingLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGroup = editingLocationGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanGroup.isEmpty else { return }
        
        savedLocations[idx].name = cleanName
        savedLocations[idx].group = cleanGroup
        
        if activeLocationId == editId {
            selectedGroup = cleanGroup
        }
        editingLocationId = nil
    }
    
    public func applyResolvedAddressToActivePreset() {
        guard let resolved = resolvedAddressGroup else { return }
        let note = formattedResolvedAddressNote
        if let activeId = activeLocationId,
           let idx = savedLocations.firstIndex(where: { $0.id == activeId }) {
            savedLocations[idx].group = resolved
            if let note = note {
                savedLocations[idx].addressNote = note
            }
            selectedGroup = resolved
        } else if !savedLocations.isEmpty {
            savedLocations[0].group = resolved
            if let note = note {
                savedLocations[0].addressNote = note
            }
            selectLocation(savedLocations[0])
        } else {
            addSavedLocation(name: "Дім", group: resolved, addressNote: note)
        }
    }
    
    public func addPresetFromResolvedAddress() {
        guard let resolved = resolvedAddressGroup else { return }
        let note = formattedResolvedAddressNote
        let defaultName = selectedStreet?.value ?? "Нова адреса"
        let nameToUse = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultName
            : newLocationName
        addSavedLocation(name: nameToUse, group: resolved, addressNote: note)
    }
    
    public var formattedResolvedAddressNote: String? {
        guard let street = selectedStreet else { return nil }
        if let house = selectedHouse {
            return "\(street.value), \(house.value)"
        } else if !houseQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(street.value), \(houseQuery.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return street.value
    }
    
    public func removeSavedLocation(_ location: SavedLocation) {
        savedLocations.removeAll { $0.id == location.id }
        if editingLocationId == location.id {
            editingLocationId = nil
        }
        if activeLocationId == location.id {
            if let first = savedLocations.first {
                selectLocation(first)
            } else {
                activeLocationId = nil
            }
        }
    }
    
    // MARK: - Address Search Actions
    public func performStreetSearch() {
        let query = streetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            streetResults = []
            addressSearchError = nil
            return
        }
        
        streetSearchTask?.cancel()
        isSearchingAddress = true
        addressSearchError = nil
        selectedStreet = nil
        selectedHouse = nil
        houseResults = []
        resolvedAddressGroup = nil
        
        let region = selectedRegion
        streetSearchTask = Task { @MainActor in
            let items = await YasnoAPIService.shared.searchStreets(region: region, query: query)
            guard !Task.isCancelled else { return }
            self.streetResults = items
            self.isSearchingAddress = false
            if items.isEmpty {
                self.addressSearchError = "Вулицю «\(query)» не знайдено. Спробуйте іншу назву."
            }
        }
    }
    
    public func pickStreet(_ street: YasnoAddressItem) {
        self.selectedStreet = street
        self.streetQuery = street.value
        self.streetResults = []
        self.selectedHouse = nil
        self.houseQuery = ""
        self.resolvedAddressGroup = nil
        self.addressSearchError = nil
        performHouseSearch()
    }
    
    public func performHouseSearch() {
        guard let street = selectedStreet else { return }
        houseSearchTask?.cancel()
        isSearchingAddress = true
        addressSearchError = nil
        
        let region = selectedRegion
        let query = houseQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        houseSearchTask = Task { @MainActor in
            let items = await YasnoAPIService.shared.searchHouses(region: region, street: street, query: query)
            guard !Task.isCancelled else { return }
            self.houseResults = items
            self.isSearchingAddress = false
            if items.isEmpty && !query.isEmpty {
                self.addressSearchError = "Будинок «\(query)» не знайдено на \(street.value)."
            }
        }
    }
    
    public func pickHouse(_ house: YasnoAddressItem) {
        guard let street = selectedStreet else { return }
        self.selectedHouse = house
        self.houseQuery = house.value
        self.houseResults = []
        self.addressSearchError = nil
        self.isSearchingAddress = true
        
        let region = selectedRegion
        Task { @MainActor in
            if let group = await YasnoAPIService.shared.resolveGroup(region: region, street: street, house: house) {
                self.resolvedAddressGroup = group
                self.newLocationGroup = group
                self.isSearchingAddress = false
                self.setGroup(group, updateActivePreset: true)
            } else {
                self.isSearchingAddress = false
                self.addressSearchError = "Не вдалося визначити чергу для буд. \(house.value)."
            }
        }
    }
    
    public func resolveHouseFromQuery() {
        guard selectedStreet != nil else {
            performStreetSearch()
            return
        }
        let cleanHouse = houseQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHouse.isEmpty else {
            performHouseSearch()
            return
        }
        
        if let existingMatch = houseResults.first(where: { $0.value.lowercased() == cleanHouse.lowercased() }) {
            pickHouse(existingMatch)
            return
        }
        
        let manualHouse = YasnoAddressItem(id: -1, value: cleanHouse)
        pickHouse(manualHouse)
    }
    
    public func toggleDayTab() {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTab = (selectedTab == 0) ? 1 : 0
        }
    }
    
    private var timerCancellable: AnyCancellable?
    private var refreshTimerCancellable: AnyCancellable?
    private var sensorTimerCancellable: AnyCancellable?
    
    public init() {
        let defaults = UserDefaults.standard
        let savedRegionId = defaults.integer(forKey: prefRegionKey)
        let region = YasnoRegion.all.first(where: { $0.id == savedRegionId }) ?? .kyiv
        let savedGroup = defaults.string(forKey: prefGroupKey) ?? "1.1"
        let savedNotifications = (defaults.object(forKey: prefNotificationsKey) as? Bool) ?? true
        let savedPinned = (defaults.object(forKey: prefPinnedToDesktopKey) as? Bool) ?? false
        let savedCountdown = (defaults.object(forKey: prefMenuBarCountdownKey) as? Bool) ?? true
        let savedCompactMenuBar = (defaults.object(forKey: prefCompactMenuBarKey) as? Bool) ?? false
        let savedLaunchAtLogin: Bool
        if let storedLaunch = defaults.object(forKey: prefLaunchAtLoginKey) as? Bool {
            savedLaunchAtLogin = storedLaunch
        } else {
            savedLaunchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
        
        if let locData = defaults.data(forKey: prefLocationsKey),
           let decoded = try? JSONDecoder().decode([SavedLocation].self, from: locData),
           !decoded.isEmpty {
            self.savedLocations = decoded
        } else {
            self.savedLocations = [
                SavedLocation.defaultHome,
                SavedLocation(id: "default_office", name: "Офіс", regionId: 25, dsoId: 902, group: "2.1")
            ]
        }
        
        self.activeLocationId = defaults.string(forKey: prefActiveLocationIdKey) ?? "default_home"
        self.launchAtLogin = savedLaunchAtLogin
        self.compactMenuBarMode = savedCompactMenuBar
        self.isPinnedToDesktop = savedPinned
        self.showMenuBarCountdown = savedCountdown
        self.selectedRegion = region
        self.selectedGroup = savedGroup
        self.newLocationGroup = savedGroup
        self.notificationsEnabled = savedNotifications
        
        if let cachedSnap = YasnoAPIService.shared.loadFromCache(regionId: region.id, group: savedGroup), !cachedSnap.isFallbackMock {
            self.snapshot = cachedSnap
        }
        if let transData = defaults.data(forKey: prefLocalTransitionsKey),
           let decodedTrans = try? JSONDecoder().decode([String: [PowerTransitionEvent]].self, from: transData) {
            self.localTransitionsByLocation = decodedTrans
        }
        if let storedNotified = defaults.stringArray(forKey: prefNotifiedOutageKeys) {
            self.notifiedOutageKeys = Set(storedNotified)
        }
        if let statesData = defaults.data(forKey: prefLastSensorStatesKey),
           let decodedStates = try? JSONDecoder().decode([String: LivePowerState].self, from: statesData) {
            self.lastKnownSensorStateByLocation = decodedStates
        }
        
        syncSensorInputsFromActiveLocation()
        syncSharedState()
        startClockTimer()
        startPeriodicRefreshTimer()
        startSensorPollingTimer()
        observeSystemWake()
        if savedNotifications {
            requestNotificationPermission()
        }
        refresh()
    }
    
    public func syncSharedState() {
        let state = SharedWidgetState(
            selectedRegionId: selectedRegion.id,
            selectedGroup: selectedGroup,
            activeLocationId: activeLocationId,
            savedLocations: savedLocations,
            selectedTab: selectedTab,
            liveSensorStatus: liveSensorStatus
        )
        SharedStateStore.save(state)
        
        // Reload WidgetKit only when something visible actually changed.
        // (Sensor polling runs every 30s; reloading on every poll exhausts the macOS widget reload budget
        // and makes the desktop widgets stop updating altogether.)
        let sensorPart: String
        if let s = liveSensorStatus {
            let lastFlip = s.transitions.last.map { "\(Int($0.timestamp.timeIntervalSince1970))-\($0.isPowerOn)" } ?? "-"
            sensorPart = "\(s.state.rawValue)|\(s.transitions.count)|\(lastFlip)"
        } else {
            sensorPart = "nil"
        }
        let snapPart = snapshot.map { "\($0.regionId)|\($0.group)|\(Int($0.lastUpdated.timeIntervalSince1970))" } ?? "nil"
        let locPart = savedLocations.map { "\($0.id):\($0.name):\($0.group):\($0.sensorType.rawValue)" }.joined(separator: ",")
        let fingerprint = "\(selectedRegion.id)|\(selectedGroup)|\(activeLocationId ?? "-")|\(selectedTab)|\(locPart)|\(sensorPart)|\(snapPart)"
        if fingerprint != lastWidgetFingerprint {
            lastWidgetFingerprint = fingerprint
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    public func refresh() {
        let targetRegion = self.selectedRegion
        let targetGroup = self.selectedGroup
        isRefreshing = true
        lastError = nil
        if !isCheckingSensor {
            refreshLiveSensor()
        }
        
        // Cancel an in-flight request for the previous preset/group, so a slow response
        // for the OLD group can never overwrite the schedule of the newly selected group.
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            do {
                let newSnapshot = try await YasnoAPIService.shared.fetchSchedule(
                    region: targetRegion,
                    group: targetGroup
                )
                guard !Task.isCancelled,
                      self.selectedRegion.id == targetRegion.id,
                      self.selectedGroup == targetGroup else { return }
                self.snapshot = newSnapshot
                self.isRefreshing = false
                self.scheduleImminentOutageNotificationIfNeeded()
                self.syncSharedState()
            } catch {
                guard !Task.isCancelled,
                      self.selectedRegion.id == targetRegion.id,
                      self.selectedGroup == targetGroup else { return }
                // Don't keep showing another group's schedule under the new group's name
                if let snap = self.snapshot, snap.regionId != targetRegion.id || snap.group != targetGroup {
                    self.snapshot = nil
                }
                self.lastError = error.localizedDescription
                self.isRefreshing = false
            }
        }
    }
    
    // MARK: - Computed Properties
    public var scheduleStatus: OutageType {
        guard let today = alignedDays.today else { return .unknown }
        if today.status.isEmergency {
            return .off
        }
        let currentMinute = ScheduleCalculator.kyivMinuteOfDay(for: currentTime)
        return ScheduleCalculator.calculateCurrentStatus(slots: today.slots, currentMinute: currentMinute)
    }
    
    public var currentStatus: OutageType {
        if let sensor = liveSensorStatus {
            switch sensor.state {
            case .online:
                return .on
            case .offline:
                return .off
            default:
                break
            }
        }
        return scheduleStatus
    }
    
    public var sensorScheduleMismatchText: String? {
        guard let sensor = liveSensorStatus else { return nil }
        let sched = scheduleStatus
        if sensor.state == .online && sched == .off {
            return "⚡️ За датчиком світло Є (за графіком — відключення)"
        }
        if sensor.state == .offline && sched == .on {
            return "⚠️ За датчиком світла НЕМАЄ (поза графіком Yasno)"
        }
        return nil
    }
    
    public var nextEvent: NextEvent {
        guard snapshot != nil, alignedDays.today != nil else {
            return NextEvent(eventType: .none, targetDate: nil, minutesRemaining: 0)
        }
        return ScheduleCalculator.calculateNextEvent(
            todaySlots: todaySlots,
            tomorrowSlots: tomorrowSlots,
            currentDate: currentTime,
            sensor: liveSensorStatus
        )
    }
    
    public var todaySlots: [OutageSlot] {
        guard let today = alignedDays.today else { return [] }
        return ScheduleCalculator.reconcileTodaySlotsWithLiveSensor(
            plannedSlots: today.slots,
            sensor: liveSensorStatus,
            currentDate: currentTime
        )
    }
    
    public var tomorrowSlots: [OutageSlot] {
        alignedDays.tomorrow?.slots ?? []
    }
    
    public var todayStatus: DayScheduleStatus {
        alignedDays.today?.status ?? .waitingForSchedule
    }
    
    public var tomorrowStatus: DayScheduleStatus {
        alignedDays.tomorrow?.status ?? .waitingForSchedule
    }
    
    public var todayOffSlots: [OutageSlot] {
        todaySlots.filter { $0.type == .off }
    }
    
    public var tomorrowOffSlots: [OutageSlot] {
        tomorrowSlots.filter { $0.type == .off }
    }
    
    public var currentMinuteOfDay: Int {
        ScheduleCalculator.kyivMinuteOfDay(for: currentTime)
    }
    
    // MARK: - Timers (Optimized to fire only when minute changes!)
    private func startClockTimer() {
        timerCancellable = Timer.publish(every: 15.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] newDate in
                guard let self = self else { return }
                let oldMin = ScheduleCalculator.kyivMinuteOfDay(for: self.currentTime)
                let newMin = ScheduleCalculator.kyivMinuteOfDay(for: newDate)
                if newMin != oldMin {
                    let dayChanged = ScheduleCalculator.kyivStartOfDay(for: self.currentTime) != ScheduleCalculator.kyivStartOfDay(for: newDate)
                    self.currentTime = newDate
                    self.checkAllLocationsScheduleNotifications()
                    if dayChanged {
                        // Midnight: fetch the new day's schedule right away instead of waiting up to 10 minutes
                        self.refresh()
                    }
                }
            }
    }
    
    private var wakeObserver: NSObjectProtocol?
    
    /// After the Mac wakes from sleep, timers may be up to hours behind: update the clock,
    /// re-fetch the schedule and re-check the sensor immediately.
    private func observeSystemWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = Date()
            // Give Wi-Fi a few seconds to reconnect after wake
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.currentTime = Date()
                self?.refresh()
            }
        }
    }
    
    private func startPeriodicRefreshTimer() {
        refreshTimerCancellable = Timer.publish(every: 600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
    
    private func startSensorPollingTimer() {
        sensorTimerCancellable = Timer.publish(every: 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.pollAllLocationsSensors()
            }
    }
    
    public func pollAllLocationsSensors() {
        Task { [weak self] in
            guard let self = self else { return }
            for loc in self.savedLocations {
                guard loc.sensorType != .disabled,
                      let target = loc.sensorTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !target.isEmpty else { continue }
                
                let result = await LiveMonitorService.shared.checkStatus(type: loc.sensorType, target: target)
                guard let newStatus = result else { continue }
                
                await MainActor.run {
                    let locId = loc.id
                    let locName = loc.name
                    let prevState = self.lastKnownSensorStateByLocation[locId]
                    
                    if newStatus.state == .online || newStatus.state == .offline {
                        if let prev = prevState, prev != newStatus.state {
                            self.sendLivePowerChangeNotification(locationName: locName, newStatus: newStatus)
                            
                            let evt = PowerTransitionEvent(
                                timestamp: newStatus.eventTimestamp ?? Date(),
                                isPowerOn: newStatus.state == .online
                            )
                            var history = (self.localTransitionsByLocation[locId] ?? []).filter {
                                Date().timeIntervalSince($0.timestamp) < 172800
                            }
                            history.append(evt)
                            self.localTransitionsByLocation[locId] = history
                            if let encoded = try? JSONEncoder().encode(self.localTransitionsByLocation) {
                                UserDefaults.standard.set(encoded, forKey: self.prefLocalTransitionsKey)
                            }
                        }
                        self.lastKnownSensorStateByLocation[locId] = newStatus.state
                        if let encodedStates = try? JSONEncoder().encode(self.lastKnownSensorStateByLocation) {
                            UserDefaults.standard.set(encodedStates, forKey: self.prefLastSensorStatesKey)
                        }
                    }
                    
                    // If this is the active location, update liveSensorStatus
                    if locId == self.activeLocation?.id {
                        self.liveSensorStatus = newStatus
                        if newStatus.state == .online || newStatus.state == .offline {
                            self.lastGoodSensorStatus = newStatus
                        }
                        if let detected = newStatus.detectedGroup, !detected.isEmpty, loc.group != detected {
                            self.handleDetectedGroup(detected, forLocationId: locId)
                        }
                        self.syncSharedState()
                    }
                }
            }
        }
    }
    
    private func sendLivePowerChangeNotification(locationName: String, newStatus: LiveSensorStatus) {
        guard notificationsEnabled else { return }
        let title: String
        let body: String
        if newStatus.state == .online {
            title = "🟢 [\(locationName)] Світло з'явилося!"
            body = newStatus.detailText ?? "Датчик зафіксував появу електроенергії."
        } else {
            title = "🔴 [\(locationName)] Світло зникло!"
            body = newStatus.detailText ?? "Датчик перестав відповідати (відключення)."
        }
        deliverNotification(
            title: title,
            body: body,
            identifier: "yasno_live_sensor_\(UUID().uuidString)"
        )
    }
    
    // MARK: - Launch at Login (Autostart)
    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("[LaunchAtLogin] Failed to update login item: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Notifications
    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    public func deliverNotification(title: String, body: String, identifier: String) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                print("[Notification] UNUserNotificationCenter error: \(error.localizedDescription)")
            }
            self?.deliverViaFallback(title: title, body: body)
        }
    }
    
    private func deliverViaFallback(title: String, body: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let cleanTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let cleanBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "display notification \"\(cleanBody)\" with title \"\(cleanTitle)\" sound name \"Glass\""
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }
    
    public func sendTestNotification() {
        requestNotificationPermission()
        deliverNotification(
            title: "🔔 Yasno: Тестове сповіщення",
            body: "Сповіщення налаштовано успішно! Повідомлення надходитимуть для всіх ваших доданих адрес.",
            identifier: "yasno_test_\(UUID().uuidString)"
        )
    }
    
    public func checkAllLocationsScheduleNotifications() {
        guard notificationsEnabled else { return }
        
        let now = self.currentTime
        let dayTimestamp = Int(ScheduleCalculator.kyivStartOfDay(for: now).timeIntervalSince1970)
        
        for loc in savedLocations {
            let region = YasnoRegion.all.first(where: { $0.id == loc.regionId }) ?? .kyiv
            guard let snap = YasnoAPIService.shared.loadFromCache(regionId: region.id, group: loc.group) else {
                continue
            }
            
            let aligned = snap.alignedDays(for: now)
            guard let today = aligned.today else { continue }
            
            let sensorStatus = (loc.id == activeLocation?.id) ? liveSensorStatus : nil
            let todaySlots = ScheduleCalculator.reconcileTodaySlotsWithLiveSensor(
                plannedSlots: today.slots,
                sensor: sensorStatus,
                currentDate: now
            )
            let tomorrowSlots = aligned.tomorrow?.slots ?? []
            let nextEvt = ScheduleCalculator.calculateNextEvent(
                todaySlots: todaySlots,
                tomorrowSlots: tomorrowSlots,
                currentDate: now,
                sensor: sensorStatus
            )
            
            guard nextEvt.isTurnOff, let targetDate = nextEvt.targetDate else { continue }
            
            let minutesRemaining = nextEvt.minutesRemaining
            let outageKey = "outage_\(loc.id)_\(nextEvt.formattedTargetTime)_\(dayTimestamp)"
            
            if minutesRemaining >= 1 && minutesRemaining <= 15 {
                if !notifiedOutageKeys.contains(outageKey) {
                    notifiedOutageKeys.insert(outageKey)
                    UserDefaults.standard.set(Array(notifiedOutageKeys), forKey: prefNotifiedOutageKeys)
                    
                    deliverNotification(
                        title: "⚡️ [\(loc.name) • Черга \(loc.group)] Відключення о \(nextEvt.formattedTargetTime)",
                        body: "До планового вимкнення світла залишилось \(minutesRemaining) хв. Зарядіть пристрої!",
                        identifier: outageKey
                    )
                }
            } else if minutesRemaining > 15 {
                let alertDate = targetDate.addingTimeInterval(-15 * 60)
                let interval = alertDate.timeIntervalSinceNow
                if interval > 0 {
                    let content = UNMutableNotificationContent()
                    content.title = "⚡️ [\(loc.name) • Черга \(loc.group)] Відключення о \(nextEvt.formattedTargetTime)"
                    content.body = "До планового вимкнення світла залишилось 15 хв. Зарядіть пристрої!"
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    let request = UNNotificationRequest(identifier: outageKey, content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }
    
    private func scheduleImminentOutageNotificationIfNeeded() {
        checkAllLocationsScheduleNotifications()
    }
}
