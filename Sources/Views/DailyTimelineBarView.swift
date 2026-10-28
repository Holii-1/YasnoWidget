import SwiftUI

public struct DailyTimelineBarView: View {
    public let slots: [OutageSlot]
    public let currentMinute: Int
    public let showNeedle: Bool
    
    public init(slots: [OutageSlot], currentMinute: Int, showNeedle: Bool = true) {
        self.slots = slots
        self.currentMinute = currentMinute
        self.showNeedle = showNeedle
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height: CGFloat = 14
                
                ZStack(alignment: .leading) {
                    // Solid dark track
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(red: 0.16, green: 0.16, blue: 0.19))
                        .frame(height: height)
                    
                    // Segments
                    HStack(spacing: 1.5) {
                        ForEach(slots) { slot in
                            let fraction = CGFloat(slot.durationMinutes) / 1440.0
                            let segmentWidth = max(2, fraction * width - 1.5)
                            
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(slotColor(slot.type))
                                .frame(width: segmentWidth, height: height)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    
                    // Current time needle (shown on Today)
                    if showNeedle {
                        let needleX = min(max(0, CGFloat(currentMinute) / 1440.0 * width), width)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 3, height: height + 6)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
                            .offset(x: needleX - 1.5, y: 0)
                    }
                }
            }
            .frame(height: 18)
            
            // Hour markers
            HStack {
                Text("00:00")
                Spacer()
                Text("06:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("24:00")
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
        }
    }
    
    private func slotColor(_ type: OutageType) -> Color {
        switch type {
        case .on:
            return Color(red: 0.18, green: 0.78, blue: 0.44)
        case .off:
            return Color(red: 0.92, green: 0.25, blue: 0.22)
        case .possible:
            return Color(red: 0.95, green: 0.58, blue: 0.12)
        case .unknown:
            return Color(red: 0.28, green: 0.28, blue: 0.32)
        }
    }
}
