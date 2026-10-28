import Foundation
import SwiftUI

// MARK: - Outage Type
public enum OutageType: String, Codable, CaseIterable {
    case on = "NotPlanned"
    case off = "Definite"
    case possible = "Possible"
    case unknown = "Unknown"
    
    public var titleUk: String {
        switch self {
        case .on: return "Світло є"
        case .off: return "Відключення"
        case .possible: return "Можливе відключення"
        case .unknown: return "Невідомо"
        }
    }
    
    public var titleEn: String {
        switch self {
        case .on: return "Power On"
        case .off: return "Power Off"
        case .possible: return "Possible Off"
        case .unknown: return "Unknown"
        }
    }
    
    public var iconName: String {
        switch self {
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        case .possible: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    public var color: Color {
        switch self {
        case .on: return Color.green
        case .off: return Color.red
        case .possible: return Color.orange
        case .unknown: return Color.gray
        }
    }
}

// MARK: - Day Schedule Status (Schedule vs Emergency Shutdowns)
public enum DayScheduleStatus: String, Codable, Equatable {
    case scheduleApplies = "ScheduleApplies"
    case emergencyShutdowns = "EmergencyShutdowns"
    case waitingForSchedule = "WaitingForSchedule"
    
    public var isEmergency: Bool {
        self == .emergencyShutdowns
    }
    
    public var isWaiting: Bool {
        self == .waitingForSchedule
    }
    
    public var titleUk: String {
        switch self {
        case .scheduleApplies: return "Діє графік"
        case .emergencyShutdowns: return "Екстрені відключення"
        case .waitingForSchedule: return "Очікується графік"
        }
    }
}

// MARK: - Live Sensor Integration (SvitloBot & Healthchecks.io)
public enum LiveSensorType: String, Codable, CaseIterable, Equatable {
    case disabled = "none"
    case svitlobot = "svitlobot"
    case healthchecks = "healthchecks"
    
    public var titleUk: String {
        switch self {
        case .disabled: return "Вимкнено"
        case .svitlobot: return "СвітлоБот"
        case .healthchecks: return "Healthchecks"
        }
    }
}

public enum LivePowerState: String, Codable, Equatable {
    case unknown = "unknown"
    case online = "online"
    case offline = "offline"
    case grace = "grace"
    case error = "error"
    
    public var isOnline: Bool { self == .online }
    public var isOffline: Bool { self == .offline }
}

public struct PowerTransitionEvent: Codable, Equatable {
    public let timestamp: Date
    public let isPowerOn: Bool
    
    public init(timestamp: Date, isPowerOn: Bool) {
        self.timestamp = timestamp
        self.isPowerOn = isPowerOn
    }
}

public struct LiveSensorStatus: Codable, Equatable {
    public let source: LiveSensorType
    public let state: LivePowerState
    public let statusText: String
    public let detailText: String?
    public let eventTimestamp: Date?
    public let checkedAt: Date
    public let transitions: [PowerTransitionEvent]
    public let detectedGroup: String?
    public let channelTitle: String?
    public let plannedHints: [OutageSlot]
    
    private enum CodingKeys: String, CodingKey {
        case source, state, statusText, detailText, eventTimestamp, checkedAt, transitions, detectedGroup, channelTitle, plannedHints
    }
    
    public init(
        source: LiveSensorType,
        state: LivePowerState,
        statusText: String,
        detailText: String? = nil,
        eventTimestamp: Date? = nil,
        checkedAt: Date = Date(),
        transitions: [PowerTransitionEvent] = [],
        detectedGroup: String? = nil,
        channelTitle: String? = nil,
        plannedHints: [OutageSlot] = []
    ) {
        self.source = source
        self.state = state
        self.statusText = statusText
        self.detailText = detailText
        self.eventTimestamp = eventTimestamp
        self.checkedAt = checkedAt
        self.transitions = transitions
        self.detectedGroup = detectedGroup
        self.channelTitle = channelTitle
        self.plannedHints = plannedHints
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decode(LiveSensorType.self, forKey: .source)
        self.state = try container.decode(LivePowerState.self, forKey: .state)
        self.statusText = try container.decode(String.self, forKey: .statusText)
        self.detailText = try container.decodeIfPresent(String.self, forKey: .detailText)
        self.eventTimestamp = try container.decodeIfPresent(Date.self, forKey: .eventTimestamp)
        self.checkedAt = (try? container.decodeIfPresent(Date.self, forKey: .checkedAt)) ?? Date()
        self.transitions = (try? container.decodeIfPresent([PowerTransitionEvent].self, forKey: .transitions)) ?? []
        self.detectedGroup = try container.decodeIfPresent(String.self, forKey: .detectedGroup)
        self.channelTitle = try container.decodeIfPresent(String.self, forKey: .channelTitle)
        self.plannedHints = (try? container.decodeIfPresent([OutageSlot].self, forKey: .plannedHints)) ?? []
    }
}

// MARK: - Saved Location (Bookmark / Preset)
public struct SavedLocation: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var regionId: Int
    public var dsoId: Int
    public var group: String
    public var addressNote: String?
    public var sensorType: LiveSensorType
    public var sensorTarget: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, regionId, dsoId, group, addressNote, sensorType, sensorTarget
    }
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        regionId: Int,
        dsoId: Int,
        group: String,
        addressNote: String? = nil,
        sensorType: LiveSensorType = .disabled,
        sensorTarget: String? = nil
    ) {
        self.id = id
        self.name = name
        self.regionId = regionId
        self.dsoId = dsoId
        self.group = group
        self.addressNote = addressNote
        self.sensorType = sensorType
        self.sensorTarget = sensorTarget
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.regionId = try container.decode(Int.self, forKey: .regionId)
        self.dsoId = try container.decode(Int.self, forKey: .dsoId)
        self.group = try container.decode(String.self, forKey: .group)
        self.addressNote = try container.decodeIfPresent(String.self, forKey: .addressNote)
        self.sensorType = (try? container.decodeIfPresent(LiveSensorType.self, forKey: .sensorType)) ?? .disabled
        self.sensorTarget = try container.decodeIfPresent(String.self, forKey: .sensorTarget)
    }
    
    public static let defaultHome = SavedLocation(
        id: "default_home",
        name: "Дім",
        regionId: 25,
        dsoId: 902,
        group: "1.1",
        addressNote: nil,
        sensorType: .disabled,
        sensorTarget: nil
    )
}

// MARK: - Shared Locations Store (App + WidgetKit Sync)
public struct SharedWidgetState: Codable {
    public var selectedRegionId: Int
    public var selectedGroup: String
    public var activeLocationId: String?
    public var savedLocations: [SavedLocation]
    public var selectedTab: Int
    public var liveSensorStatus: LiveSensorStatus?
    
    public init(
        selectedRegionId: Int,
        selectedGroup: String,
        activeLocationId: String?,
        savedLocations: [SavedLocation],
        selectedTab: Int = 0,
        liveSensorStatus: LiveSensorStatus? = nil
    ) {
        self.selectedRegionId = selectedRegionId
        self.selectedGroup = selectedGroup
        self.activeLocationId = activeLocationId
        self.savedLocations = savedLocations
        self.selectedTab = selectedTab
        self.liveSensorStatus = liveSensorStatus
    }
}

public enum SharedStateStore {
    public static let appGroupId = "group.ua.yasno.mac.widget"
    private static let stateKey = "yasno_shared_widget_state_v2"
    private static let tmpFilePath = "/private/tmp/yasno_widget_shared_state.json"
    
    public static var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
    
    public static func save(_ state: SharedWidgetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        
        // 1. Save to App Group Container file
        if let dir = groupContainerURL {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("yasno_shared_state.json")
            try? data.write(to: fileURL, options: .atomic)
        }
        
        // 2. Save to App Group UserDefaults & App UserDefaults
        UserDefaults(suiteName: appGroupId)?.set(data, forKey: stateKey)
        UserDefaults(suiteName: "ua.yasno.mac.widget")?.set(data, forKey: stateKey)
        UserDefaults.standard.set(data, forKey: stateKey)
        
        // 3. Save to /private/tmp/
        try? data.write(to: URL(fileURLWithPath: tmpFilePath), options: .atomic)
    }
    
    public static func load() -> SharedWidgetState? {
        // 1. Try App Group Container file
        if let dir = groupContainerURL {
            let fileURL = dir.appendingPathComponent("yasno_shared_state.json")
            if let data = try? Data(contentsOf: fileURL),
               let state = try? JSONDecoder().decode(SharedWidgetState.self, from: data) {
                return state
            }
        }
        
        // 2. Try /private/tmp/
        if let data = try? Data(contentsOf: URL(fileURLWithPath: tmpFilePath)),
           let state = try? JSONDecoder().decode(SharedWidgetState.self, from: data) {
            return state
        }
        
        // 3. Try Shared UserDefaults
        let suites: [UserDefaults?] = [
            UserDefaults(suiteName: appGroupId),
            UserDefaults(suiteName: "ua.yasno.mac.widget"),
            UserDefaults.standard
        ]
        for suite in suites {
            if let data = suite?.data(forKey: stateKey),
               let state = try? JSONDecoder().decode(SharedWidgetState.self, from: data) {
                return state
            }
        }
        
        return nil
    }
}

// MARK: - Address Lookup Item
public struct YasnoAddressItem: Identifiable, Codable, Equatable, Hashable {
    public let id: Int
    public let value: String
    public let fallbackGroup: String?
    
    public init(id: Int, value: String, fallbackGroup: String? = nil) {
        self.id = id
        self.value = value
        self.fallbackGroup = fallbackGroup
    }
}

// MARK: - Outage Slot
public struct OutageSlot: Identifiable, Codable, Equatable {
    public var id: String { "\(startMinutes)-\(endMinutes)-\(type.rawValue)-\(isActualFact)" }
    public let startMinutes: Int // 0 to 1440
    public let endMinutes: Int   // 0 to 1440
    public let type: OutageType
    public let isActualFact: Bool
    
    private enum CodingKeys: String, CodingKey {
        case startMinutes, endMinutes, type, isActualFact
    }
    
    public init(startMinutes: Int, endMinutes: Int, type: OutageType, isActualFact: Bool = false) {
        self.startMinutes = max(0, min(1440, startMinutes))
        self.endMinutes = max(0, min(1440, endMinutes))
        self.type = type
        self.isActualFact = isActualFact
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(Int.self, forKey: .startMinutes)
        let end = try container.decode(Int.self, forKey: .endMinutes)
        self.startMinutes = max(0, min(1440, start))
        self.endMinutes = max(0, min(1440, end))
        self.type = try container.decode(OutageType.self, forKey: .type)
        self.isActualFact = (try? container.decodeIfPresent(Bool.self, forKey: .isActualFact)) ?? false
    }
    
    public var startFormatted: String {
        formatMinutes(startMinutes)
    }
    
    public var endFormatted: String {
        formatMinutes(endMinutes)
    }
    
    public var timeRangeFormatted: String {
        "\(startFormatted) – \(endFormatted)"
    }
    
    public var durationMinutes: Int {
        max(0, endMinutes - startMinutes)
    }
    
    public var durationFormatted: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if minutes == 0 {
            return "\(hours) год"
        } else if hours == 0 {
            return "\(minutes) хв"
        } else {
            return "\(hours)г \(minutes)хв"
        }
    }
    
    public func contains(minuteOfDay: Int) -> Bool {
        return minuteOfDay >= startMinutes && minuteOfDay < endMinutes
    }
    
    private func formatMinutes(_ minutes: Int) -> String {
        let clamped = min(minutes, 1440)
        let h = clamped / 60
        let m = clamped % 60
        if h == 24 && m == 0 {
            return "24:00"
        }
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: - Day Schedule
public struct DaySchedule: Codable, Equatable {
    public let date: Date
    public let isToday: Bool
    public let slots: [OutageSlot]
    public let status: DayScheduleStatus
    
    public init(
        date: Date,
        isToday: Bool,
        slots: [OutageSlot],
        status: DayScheduleStatus = .scheduleApplies
    ) {
        self.date = date
        self.isToday = isToday
        self.slots = slots
        self.status = status
    }
    
    public var offSlots: [OutageSlot] {
        slots.filter { $0.type == .off }
    }
    
    public var possibleSlots: [OutageSlot] {
        slots.filter { $0.type == .possible }
    }
    
    public var totalOffHours: Double {
        let totalMin = offSlots.reduce(0) { $0 + $1.durationMinutes }
        return Double(totalMin) / 60.0
    }
}

// MARK: - Next Event Info
public struct NextEvent: Equatable {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        return formatter
    }()
    
    public enum EventType: Equatable {
        case turnsOff(atMinutes: Int, atDate: Date)
        case turnsOn(atMinutes: Int, atDate: Date)
        case unplannedOutage(untilMinutes: Int, atDate: Date)
        case none
    }
    
    public let eventType: EventType
    public let targetDate: Date?
    public let minutesRemaining: Int
    
    public var isTurnOff: Bool {
        if case .turnsOff = eventType { return true }
        return false
    }
    
    public var isUnplannedOutage: Bool {
        if case .unplannedOutage = eventType { return true }
        return false
    }
    
    public var isImminentTurnOff: Bool {
        isTurnOff && minutesRemaining > 0 && minutesRemaining <= 15
    }
    
    public var formattedTargetTime: String {
        guard let targetDate = targetDate else { return "--:--" }
        return Self.timeFormatter.string(from: targetDate)
    }
    
    public var formattedCountdown: String {
        if minutesRemaining <= 0 {
            return "зараз"
        }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        if hours == 0 {
            return "\(minutes) хв"
        } else if minutes == 0 {
            return "\(hours) год"
        } else {
            return "\(hours) год \(minutes) хв"
        }
    }
    
    /// Compact countdown for the top menu bar, e.g. "1г 20хв" or "15хв"
    public var formattedShortCountdown: String {
        if minutesRemaining <= 0 {
            return "зараз"
        }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        if hours == 0 {
            return "\(minutes)хв"
        } else if minutes == 0 {
            return "\(hours)г"
        } else {
            return "\(hours)г \(minutes)хв"
        }
    }
    
    public var titleUk: String {
        switch eventType {
        case .turnsOff:
            return "Вимкнення о \(formattedTargetTime)"
        case .turnsOn:
            return "Увімкнення о \(formattedTargetTime)"
        case .unplannedOutage:
            return "Поза графіком (слот до \(formattedTargetTime))"
        case .none:
            return "Без відключень"
        }
    }
    
    public var subtitleUk: String {
        switch eventType {
        case .turnsOff:
            return "через \(formattedCountdown)"
        case .turnsOn:
            return "через \(formattedCountdown)"
        case .unplannedOutage:
            return "Очікується увімкнення"
        case .none:
            return "За графіком світло є"
        }
    }
}

// MARK: - Region & DSO
public struct YasnoRegion: Identifiable, Hashable, Codable {
    public let id: Int
    public let dsoId: Int
    public let nameUk: String
    public let providerName: String
    public let availableGroups: [String]
    
    public static let kyiv = YasnoRegion(
        id: 25,
        dsoId: 902,
        nameUk: "м. Київ",
        providerName: "ДТЕК Київські електромережі",
        availableGroups: [
            "1.1", "1.2", "2.1", "2.2", "3.1", "3.2",
            "4.1", "4.2", "5.1", "5.2", "6.1", "6.2"
        ]
    )
    
    public static let kyivRegion = YasnoRegion(
        id: 25,
        dsoId: 901,
        nameUk: "Київська область",
        providerName: "ДТЕК Київські регіональні мережі",
        availableGroups: [
            "1.1", "1.2", "2.1", "2.2", "3.1", "3.2",
            "4.1", "4.2", "5.1", "5.2", "6.1", "6.2"
        ]
    )
    
    public static let dnipro = YasnoRegion(
        id: 4,
        dsoId: 903,
        nameUk: "Дніпропетровська обл.",
        providerName: "ДТЕК Дніпровські електромережі",
        availableGroups: [
            "1.1", "1.2", "2.1", "2.2", "3.1", "3.2",
            "4.1", "4.2", "5.1", "5.2", "6.1", "6.2"
        ]
    )
    
    public static let all: [YasnoRegion] = [.kyiv, .kyivRegion, .dnipro]
}

// MARK: - Full Schedule Snapshot
public struct ScheduleSnapshot: Codable, Equatable {
    public let currentStatus: OutageType
    public let currentMinuteOfDay: Int
    public let today: DaySchedule?
    public let tomorrow: DaySchedule?
    public let lastUpdated: Date
    public let regionId: Int
    public let dsoId: Int
    public let group: String
    public let isFallbackMock: Bool
    public let discoveredGroups: [String]
    
    public var isEmergencyShutdown: Bool {
        today?.status == .emergencyShutdowns
    }
    
    /// Returns (today, tomorrow) aligned to the actual Kyiv calendar day of `date`.
    /// Protects against showing yesterday's cached schedule as "today" after midnight
    /// (e.g. when the network is down or before the next 10-minute refresh).
    public func alignedDays(for date: Date = Date()) -> (today: DaySchedule?, tomorrow: DaySchedule?) {
        let targetDay = ScheduleCalculator.kyivStartOfDay(for: date)
        if let t = today, ScheduleCalculator.kyivStartOfDay(for: t.date) == targetDay {
            return (today, tomorrow)
        }
        if let tm = tomorrow, ScheduleCalculator.kyivStartOfDay(for: tm.date) == targetDay {
            // Cached "tomorrow" has become today; the new tomorrow is not known yet
            return (tm, nil)
        }
        return (nil, nil)
    }
    
    public init(
        currentStatus: OutageType,
        currentMinuteOfDay: Int,
        today: DaySchedule?,
        tomorrow: DaySchedule?,
        lastUpdated: Date,
        regionId: Int,
        dsoId: Int,
        group: String,
        isFallbackMock: Bool = false,
        discoveredGroups: [String] = []
    ) {
        self.currentStatus = currentStatus
        self.currentMinuteOfDay = currentMinuteOfDay
        self.today = today
        self.tomorrow = tomorrow
        self.lastUpdated = lastUpdated
        self.regionId = regionId
        self.dsoId = dsoId
        self.group = group
        self.isFallbackMock = isFallbackMock
        self.discoveredGroups = discoveredGroups
    }
}
