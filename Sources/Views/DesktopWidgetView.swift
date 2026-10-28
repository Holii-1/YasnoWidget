import SwiftUI

public struct DesktopWidgetView: View {
    @ObservedObject private var manager: ScheduleManager
    
    public init(manager: ScheduleManager = .shared) {
        self.manager = manager
    }
    
    private var displayedTimelineSlots: [OutageSlot] {
        manager.selectedTab == 0 ? manager.todaySlots : manager.tomorrowSlots
    }
    
    public var body: some View {
        Group {
            if manager.showSettings {
                SettingsView(manager: manager)
                    .frame(width: 296)
            } else {
                mainWidgetCard
                    .frame(width: 296)
            }
        }
        .padding(16)
        .frame(width: 328)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.11, blue: 0.13),
                            Color(red: 0.08, green: 0.08, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 16, x: 0, y: 8)
        )
        .padding(20)
    }
    
    private var mainWidgetCard: some View {
        VStack(spacing: 11) {
            // Clean Widget Header with Quick Group & Preset Switcher Menu
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.0))
                    .font(.system(size: 12, weight: .bold))
                
                Text("YASNO")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(.white)
                
                // Interactive Menu to switch Group or Preset right from the widget!
                Menu {
                    if !manager.savedLocations.isEmpty {
                        Section(header: Text("Ваші пресети")) {
                            ForEach(manager.savedLocations) { loc in
                                Button(action: {
                                    manager.selectLocation(loc)
                                }) {
                                    Text("\(loc.name) (Черга \(loc.group))")
                                }
                            }
                        }
                    }
                    
                    Menu("Швидкий вибір черги") {
                        ForEach(manager.allAvailableGroups, id: \.self) { grp in
                            Button(action: {
                                manager.setGroup(grp, updateActivePreset: false)
                            }) {
                                Text("Черга \(grp)")
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            manager.showSettings = true
                        }
                    }) {
                        Text("⚙️ Налаштування та пошук адреси...")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(manager.activeLocation?.name ?? manager.selectedRegion.nameUk) • \(manager.selectedGroup)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.20, green: 0.20, blue: 0.24))
                    )
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .fixedSize()
                
                Spacer()
                
                // Refresh button
                Button(action: { manager.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .rotationEffect(.degrees(manager.isRefreshing ? 360 : 0))
                        .animation(manager.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: manager.isRefreshing)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Оновити розклад")
                
                // Pin to Desktop toggle
                Button(action: { manager.isPinnedToDesktop.toggle() }) {
                    Image(systemName: manager.isPinnedToDesktop ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(manager.isPinnedToDesktop ? Color(red: 0.20, green: 0.84, blue: 0.48) : .white.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(manager.isPinnedToDesktop ? "Закріплено на робочому столі" : "Закріпити на робочому столі")
                
                // Settings button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        manager.showSettings.toggle()
                    }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Налаштування та пошук за адресою")
                
                // Close button (Hide to menu bar)
                Button(action: { DesktopWidgetController.shared.hideWindow() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Сховати у верхню панель")
            }
            
            // Saved Presets (Bookmarks) 1-Click Switcher Bar
            if !manager.savedLocations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(manager.savedLocations) { loc in
                            let isSelected = (manager.activeLocation?.id == loc.id)
                            Button(action: {
                                manager.selectLocation(loc)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: loc.name.lowercased().contains("дім") ? "house.fill" : (loc.name.lowercased().contains("офіс") ? "building.2.fill" : "bookmark.fill"))
                                        .font(.system(size: 9))
                                    Text("\(loc.name) (\(loc.group))")
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    if loc.sensorType != .disabled, let target = loc.sensorTarget, !target.isEmpty {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(isSelected ? .white : Color(red: 0.20, green: 0.84, blue: 0.48))
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color(red: 0.20, green: 0.52, blue: 0.96) : Color(red: 0.17, green: 0.17, blue: 0.20))
                                )
                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Edit / Add preset button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                manager.showSettings = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.65))
                                .frame(width: 22, height: 20)
                                .background(Capsule().fill(Color(red: 0.17, green: 0.17, blue: 0.20)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Додати або змінити пресет")
                    }
                }
            }
            
            // Emergency Shutdowns Banner (if active)
            if manager.isEmergencyShutdown {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ЕКСТРЕНІ ВІДКЛЮЧЕННЯ")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("Стабілізаційні графіки наразі не діють")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.65, green: 0.10, blue: 0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            
            // Status and Next Event Hero Section
            StatusBadgeView(status: manager.currentStatus, nextEvent: manager.nextEvent)
            
            // Live Sensor Banner (SvitloBot / Healthchecks.io)
            if let sensor = manager.liveSensorStatus {
                liveSensorBanner(sensor)
            }
            
            // 24h Timeline Bar (updates for Today / Tomorrow)
            DailyTimelineBarView(
                slots: displayedTimelineSlots,
                currentMinute: manager.currentMinuteOfDay,
                showNeedle: manager.selectedTab == 0
            )
            
            // Divider line
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            
            // Arrow-switched Today / Tomorrow schedule slots
            ScheduleSlotsListView(
                todaySlots: manager.todaySlots,
                tomorrowSlots: manager.tomorrowSlots,
                todayStatus: manager.todayStatus,
                tomorrowStatus: manager.tomorrowStatus,
                selectedTab: manager.selectedTab,
                onTabChanged: { newTab in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        manager.selectedTab = newTab
                    }
                }
            )
        }
    }
    
    private func liveSensorBanner(_ sensor: LiveSensorStatus) -> some View {
        let dotColor: Color = {
            switch sensor.state {
            case .online: return Color(red: 0.20, green: 0.84, blue: 0.48)
            case .offline: return Color(red: 1.0, green: 0.27, blue: 0.23)
            case .grace, .error: return Color.orange
            case .unknown: return Color.gray
            }
        }()
        
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(dotColor)
                
                Text(sensor.statusText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Button(action: {
                    manager.refreshLiveSensor()
                }) {
                    Image(systemName: manager.isCheckingSensor ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Оновити статус датчика")
            }
            
            if let detail = sensor.detailText, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            
            if let mismatch = manager.sensorScheduleMismatchText {
                Text(mismatch)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(sensor.state == .online ? Color(red: 0.20, green: 0.84, blue: 0.48) : Color.orange)
                    .lineLimit(1)
            }
            
            if let detected = manager.detectedGroupFromSensor, detected != manager.selectedGroup {
                HStack(spacing: 4) {
                    Text("💡 Черга датчика: \(detected)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            manager.applyDetectedGroup()
                        }
                    }) {
                        Text("Застосувати")
                            .font(.system(size: 8, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .foregroundColor(.black)
                            .cornerRadius(3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(dotColor.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(dotColor.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
