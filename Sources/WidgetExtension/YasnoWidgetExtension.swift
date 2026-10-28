import WidgetKit
import SwiftUI

// MARK: - Widget Timeline Entry
public struct YasnoWidgetEntry: TimelineEntry {
    public let date: Date
    public let snapshot: ScheduleSnapshot
    public let currentStatus: OutageType
    public let nextEvent: NextEvent
    public let group: String
    public let presetName: String
    public let regionName: String
    public let selectedTab: Int
    public let liveSensorStatus: LiveSensorStatus?
}

// MARK: - Timeline Provider
public struct YasnoTimelineProvider: TimelineProvider {
    public init() {}
    
    public func placeholder(in context: Context) -> YasnoWidgetEntry {
        makeMockEntry(for: Date())
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (YasnoWidgetEntry) -> Void) {
        let sharedState = SharedStateStore.load()
        if let cached = YasnoAPIService.shared.loadFromCache(regionId: sharedState?.selectedRegionId, group: sharedState?.selectedGroup) ?? YasnoAPIService.shared.loadFromCache() {
            completion(makeEntry(from: cached, sharedState: sharedState, at: Date()))
        } else {
            completion(makeMockEntry(for: Date()))
        }
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<YasnoWidgetEntry>) -> Void) {
        let currentDate = Date()
        let sharedState = SharedStateStore.load()
        let targetRegionId = sharedState?.selectedRegionId ?? 25
        let targetGroup = sharedState?.selectedGroup ?? "1.1"
        let region = YasnoRegion.all.first(where: { $0.id == targetRegionId }) ?? .kyiv
        
        // Fast path: if we already have a fresh cached snapshot (< 10 minutes old) for this exact group, return immediately!
        if let cached = YasnoAPIService.shared.loadFromCache(regionId: targetRegionId, group: targetGroup),
           !cached.isFallbackMock,
           currentDate.timeIntervalSince(cached.lastUpdated) < 600 {
            let timeline = buildTimeline(from: cached, sharedState: sharedState, currentDate: currentDate)
            completion(timeline)
            return
        }
        
        Task {
            let snapshot: ScheduleSnapshot
            if let liveSnapshot = try? await YasnoAPIService.shared.fetchSchedule(region: region, group: targetGroup) {
                snapshot = liveSnapshot
            } else if let cached = YasnoAPIService.shared.loadFromCache(regionId: targetRegionId, group: targetGroup) ?? YasnoAPIService.shared.loadFromCache() {
                snapshot = cached
            } else {
                let samples = ScheduleCalculator.makeSampleSlots()
                let currentMinute = ScheduleCalculator.kyivMinuteOfDay(for: currentDate)
                let status = ScheduleCalculator.calculateCurrentStatus(slots: samples.today, currentMinute: currentMinute)
                snapshot = ScheduleSnapshot(
                    currentStatus: status,
                    currentMinuteOfDay: currentMinute,
                    today: DaySchedule(date: currentDate, isToday: true, slots: samples.today),
                    tomorrow: DaySchedule(date: ScheduleCalculator.kyivStartOfNextDay(for: currentDate), isToday: false, slots: samples.tomorrow),
                    lastUpdated: currentDate,
                    regionId: region.id,
                    dsoId: region.dsoId,
                    group: targetGroup,
                    isFallbackMock: true
                )
            }
            
            let timeline = buildTimeline(from: snapshot, sharedState: sharedState, currentDate: currentDate)
            completion(timeline)
        }
    }
    
    private func buildTimeline(
        from snapshot: ScheduleSnapshot,
        sharedState: SharedWidgetState?,
        currentDate: Date
    ) -> Timeline<YasnoWidgetEntry> {
        let aligned = snapshot.alignedDays(for: currentDate)
        let todaySlots = aligned.today?.slots ?? []
        var entries: [YasnoWidgetEntry] = []
        let kyivStart = ScheduleCalculator.kyivStartOfDay(for: currentDate)
        let currentMin = ScheduleCalculator.kyivMinuteOfDay(for: currentDate)
        
        entries.append(makeEntry(from: snapshot, sharedState: sharedState, at: currentDate, now: currentDate))
        
        for slot in todaySlots where slot.startMinutes > currentMin {
            let entryDate = ScheduleCalculator.kyivDate(dayStart: kyivStart, minutes: slot.startMinutes)
            entries.append(makeEntry(from: snapshot, sharedState: sharedState, at: entryDate, now: currentDate))
        }
        
        let nextReload = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        return Timeline(entries: entries, policy: .after(nextReload))
    }
    
    private func makeEntry(from snapshot: ScheduleSnapshot, sharedState: SharedWidgetState?, at date: Date, now: Date = Date()) -> YasnoWidgetEntry {
        let aligned = snapshot.alignedDays(for: date)
        let sensor = sharedState?.liveSensorStatus
        let rawTodaySlots = aligned.today?.slots ?? []
        let tomorrowSlots = aligned.tomorrow?.slots ?? []
        
        let isFutureEntry = date.timeIntervalSince(now) > 60
        let todaySlots: [OutageSlot]
        if isFutureEntry {
            todaySlots = ScheduleCalculator.reconcileForFutureEntry(
                plannedSlots: rawTodaySlots,
                sensor: sensor,
                now: now,
                entryDate: date
            )
        } else {
            todaySlots = ScheduleCalculator.reconcileTodaySlotsWithLiveSensor(
                plannedSlots: rawTodaySlots,
                sensor: sensor,
                currentDate: date
            )
        }
        
        let minOfDay = ScheduleCalculator.kyivMinuteOfDay(for: date)
        let scheduleStatus: OutageType = (aligned.today?.status.isEmergency == true)
            ? .off
            : ScheduleCalculator.calculateCurrentStatus(slots: todaySlots, currentMinute: minOfDay)
        
        let effectiveStatus: OutageType
        if abs(date.timeIntervalSinceNow) < 120, let sensor = sensor {
            switch sensor.state {
            case .online: effectiveStatus = .on
            case .offline: effectiveStatus = .off
            default: effectiveStatus = scheduleStatus
            }
        } else {
            effectiveStatus = scheduleStatus
        }
        
        let next = ScheduleCalculator.calculateNextEvent(
            todaySlots: todaySlots,
            tomorrowSlots: tomorrowSlots,
            currentDate: date,
            sensor: abs(date.timeIntervalSinceNow) < 120 ? sensor : nil
        )
        let region = YasnoRegion.all.first(where: { $0.id == snapshot.regionId }) ?? .kyiv
        
        let activeLocName: String
        if let state = sharedState,
           let loc = state.savedLocations.first(where: { $0.id == state.activeLocationId }) ?? state.savedLocations.first(where: { $0.group == snapshot.group }) {
            activeLocName = loc.name
        } else {
            activeLocName = region.nameUk
        }
        
        let tab = sharedState?.selectedTab ?? 0
        
        let reconciledSnapshot: ScheduleSnapshot
        if let origToday = aligned.today {
            let newToday = DaySchedule(date: origToday.date, isToday: origToday.isToday, slots: todaySlots, status: origToday.status)
            reconciledSnapshot = ScheduleSnapshot(
                currentStatus: effectiveStatus,
                currentMinuteOfDay: minOfDay,
                today: newToday,
                tomorrow: aligned.tomorrow,
                lastUpdated: snapshot.lastUpdated,
                regionId: snapshot.regionId,
                dsoId: snapshot.dsoId,
                group: snapshot.group,
                isFallbackMock: snapshot.isFallbackMock,
                discoveredGroups: snapshot.discoveredGroups
            )
        } else {
            reconciledSnapshot = snapshot
        }
        
        return YasnoWidgetEntry(
            date: date,
            snapshot: reconciledSnapshot,
            currentStatus: effectiveStatus,
            nextEvent: next,
            group: snapshot.group,
            presetName: activeLocName,
            regionName: region.nameUk,
            selectedTab: tab,
            liveSensorStatus: sensor
        )
    }
    
    private func makeMockEntry(for date: Date) -> YasnoWidgetEntry {
        let samples = ScheduleCalculator.makeSampleSlots()
        let currentMinute = ScheduleCalculator.kyivMinuteOfDay(for: date)
        let status = ScheduleCalculator.calculateCurrentStatus(slots: samples.today, currentMinute: currentMinute)
        let snapshot = ScheduleSnapshot(
            currentStatus: status,
            currentMinuteOfDay: currentMinute,
            today: DaySchedule(date: date, isToday: true, slots: samples.today),
            tomorrow: DaySchedule(date: ScheduleCalculator.kyivStartOfNextDay(for: date), isToday: false, slots: samples.tomorrow),
            lastUpdated: date,
            regionId: 25,
            dsoId: 902,
            group: "1.1",
            isFallbackMock: true
        )
        return makeEntry(from: snapshot, sharedState: nil, at: date, now: date)
    }
}

// MARK: - Widget Views
struct YasnoWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: YasnoTimelineProvider.Entry
    
    private static let switchDayURL = URL(string: "yasnowidget://switch-day")!
    private static let switchPresetURL = URL(string: "yasnowidget://switch-preset")!
    
    private var statusAccent: Color {
        switch entry.currentStatus {
        case .on: return Color(red: 0.20, green: 0.84, blue: 0.48)
        case .off: return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .possible: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .unknown: return Color.gray
        }
    }
    
    private var activeDayStatus: DayScheduleStatus {
        entry.selectedTab == 0
            ? (entry.snapshot.today?.status ?? .scheduleApplies)
            : (entry.snapshot.tomorrow?.status ?? .scheduleApplies)
    }
    
    private var activeDaySlots: [OutageSlot] {
        entry.selectedTab == 0
            ? (entry.snapshot.today?.slots ?? [])
            : (entry.snapshot.tomorrow?.slots ?? [])
    }
    
    private var activeDayOffSlots: [OutageSlot] {
        activeDaySlots.filter { $0.type == .off || $0.type == .possible }
    }
    
    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallWidgetView
                    .widgetURL(Self.switchPresetURL)
            case .systemMedium:
                mediumWidgetView
            case .systemLarge:
                largeWidgetView
            default:
                mediumWidgetView
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.11, blue: 0.13),
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // Interactive Preset / Group Switcher Link for WidgetKit
    private var widgetPresetSwitcherButton: some View {
        Link(destination: Self.switchPresetURL) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.0))
                Text("\(entry.presetName) • \(entry.group)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(red: 0.18, green: 0.18, blue: 0.22))
            )
        }
    }
    
    // Interactive Arrow Switcher for WidgetKit using URL Links
    private var widgetDayArrowHeader: some View {
        Link(destination: Self.switchDayURL) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 22, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(red: 0.18, green: 0.18, blue: 0.21))
                    )
                
                Text(entry.selectedTab == 0 ? "Сьогодні" : "Завтра")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 22, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(red: 0.18, green: 0.18, blue: 0.21))
                    )
            }
        }
    }
    
    // Small Widget
    private var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(statusAccent)
                    .frame(width: 8, height: 8)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.0))
                    Text("\(entry.presetName) • \(entry.group)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            
            Spacer()
            
            Text(entry.currentStatus.titleUk.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(statusAccent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nextEvent.titleUk)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(entry.nextEvent.subtitleUk)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }
    
    // Medium Widget (with interactive Preset Switcher & < Сьогодні / Завтра > arrows)
    private var mediumWidgetView: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusAccent)
                        .frame(width: 8, height: 8)
                    widgetPresetSwitcherButton
                }
                Spacer()
                widgetDayArrowHeader
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.nextEvent.titleUk)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text(entry.nextEvent.subtitleUk)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if activeDayStatus == .waitingForSchedule && activeDayOffSlots.isEmpty {
                        Text("Очікується графік")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    } else if activeDayOffSlots.isEmpty {
                        Text("Відключень немає")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.48))
                    } else {
                        ForEach(activeDayOffSlots.prefix(2)) { slot in
                            Text(slot.timeRangeFormatted)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(slot.type == .off ? Color(red: 1.0, green: 0.45, blue: 0.42) : Color(red: 1.0, green: 0.72, blue: 0.28))
                        }
                    }
                }
            }
            
            DailyTimelineBarView(
                slots: activeDaySlots,
                currentMinute: ScheduleCalculator.kyivMinuteOfDay(for: entry.date),
                showNeedle: entry.selectedTab == 0
            )
        }
    }
    
    // Large Widget (with interactive Preset Switcher & < Сьогодні / Завтра > arrows)
    private var largeWidgetView: some View {
        VStack(spacing: 10) {
            HStack {
                widgetPresetSwitcherButton
                Spacer()
                widgetDayArrowHeader
            }
            
            if entry.snapshot.isEmergencyShutdown {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("ЕКСТРЕНІ ВІДКЛЮЧЕННЯ — Графіки не діють")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.85, green: 0.15, blue: 0.15))
                )
            }
            
            StatusBadgeView(status: entry.currentStatus, nextEvent: entry.nextEvent)
            
            if let sensor = entry.liveSensorStatus {
                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(sensor.state == .online ? Color(red: 0.20, green: 0.84, blue: 0.48) : (sensor.state == .offline ? Color(red: 1.0, green: 0.27, blue: 0.23) : .orange))
                    Text(sensor.statusText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let detail = sensor.detailText, !detail.isEmpty {
                        Text("• \(detail)")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
            
            DailyTimelineBarView(
                slots: activeDaySlots,
                currentMinute: ScheduleCalculator.kyivMinuteOfDay(for: entry.date),
                showNeedle: entry.selectedTab == 0
            )
            
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            
            // Slots for active day
            if activeDayStatus == .waitingForSchedule && activeDayOffSlots.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Графік на цей день ще очікується")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.22, green: 0.18, blue: 0.12))
                )
            } else if activeDayOffSlots.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.48))
                    Text("Відключень не заплановано")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.14, green: 0.18, blue: 0.15))
                )
            } else {
                VStack(spacing: 5) {
                    ForEach(activeDayOffSlots) { slot in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(slot.type == .off ? Color(red: 1.0, green: 0.27, blue: 0.23) : Color(red: 1.0, green: 0.62, blue: 0.04))
                                .frame(width: 7, height: 7)
                            Text(slot.timeRangeFormatted)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            if slot.isActualFact {
                                Text(slot.type == .possible ? "МОЖЛИВО" : "ФАКТ")
                                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(slot.type == .possible ? Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.22) : Color.white.opacity(0.14))
                                    )
                                    .foregroundColor(slot.type == .possible ? Color(red: 1.0, green: 0.72, blue: 0.28) : .white.opacity(0.85))
                            }
                            Spacer()
                            Text(slot.durationFormatted)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(slot.type == .off ? Color(red: 0.30, green: 0.12, blue: 0.13) : Color(red: 0.30, green: 0.22, blue: 0.10))
                                )
                                .foregroundColor(slot.type == .off ? Color(red: 1.0, green: 0.45, blue: 0.42) : Color(red: 1.0, green: 0.72, blue: 0.28))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.15, green: 0.15, blue: 0.18))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Widget Definition
@main
public struct YasnoWidget: Widget {
    private let kind: String = "YasnoWidget"
    
    public init() {}
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YasnoTimelineProvider()) { entry in
            YasnoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Yasno Графіки")
        .description("Час увімкнення та вимкнення електроенергії за графіками Yasno.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
