import SwiftUI

public struct ScheduleSlotsListView: View {
    public let todaySlots: [OutageSlot]
    public let tomorrowSlots: [OutageSlot]
    public let todayStatus: DayScheduleStatus
    public let tomorrowStatus: DayScheduleStatus
    public let selectedTab: Int
    private let onTabChanged: ((Int) -> Void)?
    
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        formatter.dateFormat = "d MMM"
        return formatter
    }()
    
    public init(
        todaySlots: [OutageSlot],
        tomorrowSlots: [OutageSlot],
        todayStatus: DayScheduleStatus = .scheduleApplies,
        tomorrowStatus: DayScheduleStatus = .scheduleApplies,
        selectedTab: Int = 0,
        onTabChanged: ((Int) -> Void)? = nil
    ) {
        self.todaySlots = todaySlots
        self.tomorrowSlots = tomorrowSlots
        self.todayStatus = todayStatus
        self.tomorrowStatus = tomorrowStatus
        self.selectedTab = selectedTab
        self.onTabChanged = onTabChanged
    }
    
    private var activeDayStatus: DayScheduleStatus {
        selectedTab == 0 ? todayStatus : tomorrowStatus
    }
    
    private var activeSlots: [OutageSlot] {
        let all = selectedTab == 0 ? todaySlots : tomorrowSlots
        return all.filter { slot in slot.type == .off || slot.type == .possible }
    }
    
    private var totalOffMinutes: Int {
        var total = 0
        for slot in activeSlots {
            if slot.type == .off {
                total += slot.durationMinutes
            }
        }
        return total
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Arrow Navigation Header
            HStack(spacing: 8) {
                Button(action: { switchDay() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(red: 0.22, green: 0.22, blue: 0.26))
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 36, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: { switchDay() }) {
                    HStack(spacing: 6) {
                        Text(selectedTab == 0 ? "Сьогодні" : "Завтра")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("•")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                        
                        Text(formattedDayString(offsetDays: selectedTab))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: { switchDay() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(red: 0.22, green: 0.22, blue: 0.26))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 36, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Slots list or status state
            if activeDayStatus == .emergencyShutdowns {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text("Діють екстрені відключення")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.26, green: 0.12, blue: 0.13))
                )
            } else if activeDayStatus == .waitingForSchedule && activeSlots.isEmpty {
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
            } else if activeSlots.isEmpty {
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
                    ForEach(activeSlots) { slot in
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
                    
                    // Summary total
                    HStack {
                        Text("Всього без світла:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                        Text(formatDuration(minutes: totalOffMinutes))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.40, blue: 0.36))
                    }
                    .padding(.top, 2)
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private func switchDay() {
        let nextTab = (selectedTab == 0) ? 1 : 0
        onTabChanged?(nextTab)
    }
    
    private func formattedDayString(offsetDays: Int) -> String {
        let date = ScheduleCalculator.kyivCalendar.date(byAdding: .day, value: offsetDays, to: ScheduleCalculator.kyivStartOfDay(for: Date())) ?? Date()
        return Self.dayFormatter.string(from: date)
    }
    
    private func formatDuration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h) год" }
        return "\(h) год \(m) хв"
    }
}
