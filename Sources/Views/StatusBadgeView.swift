import SwiftUI

public struct StatusBadgeView: View {
    public let status: OutageType
    public let nextEvent: NextEvent
    
    private static let hourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        return formatter
    }()
    
    public init(status: OutageType, nextEvent: NextEvent) {
        self.status = status
        self.nextEvent = nextEvent
    }
    
    private var accentColor: Color {
        switch status {
        case .on: return Color(red: 0.20, green: 0.84, blue: 0.48)
        case .off: return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .possible: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .unknown: return Color.gray
        }
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: Status & Countdown
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: accentColor.opacity(0.6), radius: 4, x: 0, y: 0)
                    
                    Text(status.titleUk.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(accentColor)
                }
                
                Text(nextEvent.titleUk)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text(nextEvent.subtitleUk)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Right: Big Target Clock Badge
            if let targetDate = nextEvent.targetDate {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: nextEvent.isUnplannedOutage ? "exclamationmark.triangle.fill" : (nextEvent.isTurnOff ? "bolt.slash.fill" : "bolt.fill"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(nextEvent.isUnplannedOutage ? Color.orange : (nextEvent.isTurnOff ? Color(red: 1.0, green: 0.35, blue: 0.30) : Color(red: 0.20, green: 0.84, blue: 0.48)))
                        Text(nextEvent.isUnplannedOutage ? "ЗА ГРАФІКОМ ДО" : (nextEvent.isTurnOff ? "ВИМКНЕННЯ" : "УВІМКНЕННЯ"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    
                    Text(Self.hourMinuteFormatter.string(from: targetDate))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
    }
}
