import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var manager: ScheduleManager
    @Environment(\.presentationMode) private var presentationMode
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    public init(manager: ScheduleManager) {
        self.manager = manager
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 13, weight: .bold))
                    Text("Налаштування Yasno")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        manager.showSettings = false
                    }
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack(spacing: 4) {
                        Text("Готово")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    
                    // 1. Saved Presets (Locations) with Edit & Add via Picker
                    presetsSection
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                    
                    // 2. Live Power Sensor (SvitloBot & Healthchecks.io)
                    liveSensorSection
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                    
                    // 3. Address Search (Street + Real House Picker -> Group)
                    addressSearchSection
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                    
                    // 3. Region & Direct Group Picker
                    regionAndGroupPickerSection
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                    
                    // 4. Menu Bar Countdown & Notifications Toggles
                    togglesSection
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                    
                    // 5. Refresh and Quit
                    footerSection
                }
                .frame(width: 284, alignment: .leading)
                .padding(.trailing, 8)
            }
        }
        .frame(width: 296, height: 450)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 1. Presets Section
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🏠 Збережені пресети (Локації)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            
            ForEach(manager.savedLocations) { loc in
                if manager.editingLocationId == loc.id {
                    // Inline Edit Mode for Preset
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Редагування пресету:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                        
                        HStack(spacing: 6) {
                            TextField("Назва", text: $manager.editingLocationName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 11))
                            
                            Picker("Черга", selection: $manager.editingLocationGroup) {
                                ForEach(manager.allAvailableGroups, id: \.self) { grp in
                                    Text("Черга \(grp)").tag(grp)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 95)
                        }
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                manager.saveEditedLocation()
                            }) {
                                Text("Зберегти")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                manager.cancelEditingLocation()
                            }) {
                                Text("Скасувати")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white.opacity(0.8))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Spacer()
                        }
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(8)
                } else {
                    // Normal Preset Row
                    let isSelected = manager.activeLocation?.id == loc.id
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isSelected ? Color.green : Color.white.opacity(0.25))
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text("\(loc.name) • Черга \(loc.group)")
                                    .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                if loc.sensorType != .disabled, let target = loc.sensorTarget, !target.isEmpty {
                                    Text(loc.sensorType == .svitlobot ? "СвітлоБот" : "HC")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.25))
                                        .foregroundColor(.green)
                                        .cornerRadius(3)
                                }
                            }
                            if let note = loc.addressNote, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer(minLength: 4)
                        
                        if !isSelected {
                            Button(action: {
                                manager.selectLocation(loc)
                            }) {
                                Text("Обрати")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Edit button (change name & group)
                        Button(action: {
                            manager.startEditingLocation(loc)
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Змінити назву або чергу пресету")
                        
                        if manager.savedLocations.count > 1 {
                            Button(action: {
                                manager.removeSavedLocation(loc)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.85))
                                    .frame(width: 22, height: 22)
                                    .background(Color.red.opacity(0.12))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Видалити пресет")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    .cornerRadius(7)
                }
            }
            
            // Add New Preset Row (using a Group Picker instead of manual text input!)
            VStack(alignment: .leading, spacing: 5) {
                Text("Додати новий пресет:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                HStack(spacing: 6) {
                    TextField("Назва пресету", text: $manager.newLocationName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))
                    
                    Picker("Черга", selection: $manager.newLocationGroup) {
                        ForEach(manager.allAvailableGroups, id: \.self) { grp in
                            Text("Черга \(grp)").tag(grp)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)
                    
                    Button(action: {
                        manager.addSavedLocation(
                            name: manager.newLocationName,
                            group: manager.newLocationGroup
                        )
                    }) {
                        Text("+ Додати")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 2)
        }
    }
    
    // MARK: - 2. Live Sensor Section (SvitloBot & Healthchecks.io)
    private var liveSensorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("📡 Живий датчик світла")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("Пресет: \(manager.activeLocation?.name ?? "Дім")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            }
            
            // 3-Button Mode Selector
            HStack(spacing: 5) {
                ForEach(LiveSensorType.allCases, id: \.self) { type in
                    let isSelected = (manager.sensorInputType == type)
                    Button(action: {
                        manager.setSensorTypeForActiveLocation(type)
                    }) {
                        Text(type.titleUk)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if manager.sensorInputType != .disabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField(
                            manager.sensorInputType == .svitlobot
                                ? "@канал_будинку або ключ"
                                : "Read-Only API Key / Badge URL",
                            text: $manager.sensorInputTarget,
                            onCommit: {
                                manager.saveSensorConfigForActiveLocation(
                                    type: manager.sensorInputType,
                                    target: manager.sensorInputTarget
                                )
                            }
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))
                        
                        Button(action: {
                            manager.saveSensorConfigForActiveLocation(
                                type: manager.sensorInputType,
                                target: manager.sensorInputTarget
                            )
                        }) {
                            Text("Зберегти")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Text(
                        manager.sensorInputType == .svitlobot
                            ? "Введіть публічний Telegram-канал СвітлоБота (напр. @svitlo_...) або ваш channel_key."
                            : "Для ESP32: вставте Read-Only API Key (Settings → API) або Badge URL з Healthchecks.io."
                    )
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    
                    if manager.isCheckingSensor && manager.liveSensorStatus == nil {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Перевірка зв'язку з датчиком...")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    } else if let status = manager.liveSensorStatus {
                        let statusColor: Color = {
                            switch status.state {
                            case .online: return .green
                            case .offline: return .red
                            case .grace, .error: return .orange
                            case .unknown: return .gray
                            }
                        }()
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 7, height: 7)
                                Text(status.statusText)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(statusColor)
                                    .lineLimit(1)
                                Spacer()
                            }
                            if let detail = status.detailText, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(7)
                        .background(statusColor.opacity(0.12))
                        .cornerRadius(6)
                    }
                    
                    // Auto-Detected Group Notice or 1-Click Apply Banner
                    if let notice = manager.autoDetectedGroupNotice {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.48))
                                .font(.system(size: 11, weight: .bold))
                            Text(notice)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.48))
                                .lineLimit(2)
                            Spacer()
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    manager.autoDetectedGroupNotice = nil
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(6)
                        .background(Color(red: 0.20, green: 0.84, blue: 0.48).opacity(0.12))
                        .cornerRadius(6)
                    } else if let detected = manager.detectedGroupFromSensor, detected != manager.selectedGroup {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                                .font(.system(size: 11, weight: .bold))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Виявлено чергу \(detected)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Знайдено в описі/повідомленнях каналу")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            
                            Spacer(minLength: 4)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    manager.applyDetectedGroup()
                                }
                            }) {
                                Text("Застосувати")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.orange)
                                    .foregroundColor(.black)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(6)
                        .background(Color.orange.opacity(0.14))
                        .cornerRadius(6)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(7)
            }
        }
    }
    
    // MARK: - 2. Address Search Section
    private var addressSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔍 Пошук черги за адресою")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            
            // Step 1: Street Search
            HStack(spacing: 6) {
                TextField("Вулиця (напр. Хрещатик)", text: $manager.streetQuery, onCommit: {
                    manager.performStreetSearch()
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 11))
                
                Button(action: {
                    manager.performStreetSearch()
                }) {
                    Text("Знайти")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Street Results List
            if !manager.streetResults.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Оберіть вулицю зі списку:")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                    
                    ForEach(manager.streetResults.prefix(6)) { street in
                        Button(action: {
                            manager.pickStreet(street)
                        }) {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                                Text(street.value)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("Обрати")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Step 2: House Search & Selection (once street is picked)
            if let selectedStreet = manager.selectedStreet {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Вулиця:")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        Text(selectedStreet.value)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    
                    HStack(spacing: 6) {
                        TextField("№ будинку", text: $manager.houseQuery, onCommit: {
                            manager.performHouseSearch()
                        })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))
                        
                        Button(action: {
                            manager.performHouseSearch()
                        }) {
                            Text("Пошук №")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.14))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            manager.resolveHouseFromQuery()
                        }) {
                            Text("Визначити")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Real House Chips from Yasno API
                    if !manager.houseResults.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Оберіть ваш номер будинку:")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                                ForEach(manager.houseResults.prefix(16)) { house in
                                    Button(action: {
                                        manager.pickHouse(house)
                                    }) {
                                        Text(house.value)
                                            .font(.system(size: 11, weight: manager.selectedHouse?.id == house.id ? .bold : .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 4)
                                            .background(manager.selectedHouse?.id == house.id ? Color.accentColor : Color.white.opacity(0.1))
                                            .foregroundColor(.white)
                                            .cornerRadius(5)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(7)
            }
            
            if manager.isSearchingAddress {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Пошук у базі Yasno...")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            if let errorMsg = manager.addressSearchError {
                Text("⚠️ \(errorMsg)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            // Step 3: Resolved Group Result + Apply to Preset Buttons
            if let resolved = manager.resolvedAddressGroup {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Знайдено чергу: \(resolved)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                            if let note = manager.formattedResolvedAddressNote {
                                Text(note)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 6) {
                        if let activeLoc = manager.activeLocation {
                            Button(action: {
                                manager.applyResolvedAddressToActivePreset()
                            }) {
                                Text("Зберегти для «\(activeLoc.name)»")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Button(action: {
                            manager.addPresetFromResolvedAddress()
                        }) {
                            Text("+ Як новий пресет")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(8)
                .background(Color.green.opacity(0.12))
                .cornerRadius(7)
            }
        }
    }
    
    // MARK: - 3. Region & Direct Group Picker Section
    private var regionAndGroupPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⚡️ Регіон та швидкий вибір черги")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            
            HStack {
                Text("Регіон:")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Picker("", selection: $manager.selectedRegion) {
                    ForEach(YasnoRegion.all) { region in
                        Text(region.nameUk).tag(region)
                    }
                }
                .labelsHidden()
                .frame(width: 155, alignment: .trailing)
            }
            
            HStack {
                Text("Поточна черга:")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Picker("", selection: Binding(
                    get: { manager.selectedGroup },
                    set: { newGroup in manager.setGroup(newGroup, updateActivePreset: true) }
                )) {
                    ForEach(manager.allAvailableGroups, id: \.self) { grp in
                        Text("Черга \(grp)").tag(grp)
                    }
                }
                .labelsHidden()
                .frame(width: 155, alignment: .trailing)
            }
        }
    }
    
    // MARK: - 4. Toggles Section
    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("🖥 Вигляд у верхній панелі (Топбар)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 6) {
                    Button(action: {
                        manager.compactMenuBarMode = false
                    }) {
                        VStack(spacing: 2) {
                            Text("Дефолтний")
                                .font(.system(size: 11, weight: !manager.compactMenuBarMode ? .bold : .medium))
                                .foregroundColor(.white)
                            Text("🟢 Вимкнуть: 14:00")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(!manager.compactMenuBarMode ? Color.accentColor : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        manager.compactMenuBarMode = true
                    }) {
                        VStack(spacing: 2) {
                            Text("Компактний")
                                .font(.system(size: 11, weight: manager.compactMenuBarMode ? .bold : .medium))
                                .foregroundColor(.white)
                            Text("🟢 14:00 (для чолки)")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(manager.compactMenuBarMode ? Color.accentColor : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            settingsToggleRow(
                title: "⏳ Таймер залишку часу в топбарі",
                subtitle: "Додавати зворотний відлік «(1г 20хв)» біля часу",
                isOn: $manager.showMenuBarCountdown
            )
            
            settingsToggleRow(
                title: "🚀 Автозапуск при старті Mac",
                subtitle: "Автоматично запускати Yasno при вході в систему",
                isOn: $manager.launchAtLogin
            )
            
            settingsToggleRow(
                title: "🔔 Сповіщення за 15 хв до відключення",
                subtitle: "Для всіх збережених профілів та датчиків",
                isOn: $manager.notificationsEnabled
            )
            
            if manager.notificationsEnabled {
                HStack {
                    Button(action: {
                        manager.sendTestNotification()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "bell.badge.fill")
                            Text("Надіслати тестове сповіщення")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.accentColor.opacity(0.14))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func settingsToggleRow(title: String, subtitle: String?, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .scaleEffect(0.85)
        }
    }
    
    // MARK: - 5. Footer Section
    private var footerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: {
                    manager.refresh()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text(manager.isRefreshing ? "Оновлення..." : "Оновити розклад")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(manager.isRefreshing)
                
                Spacer()
                
                if let lastUpdated = manager.snapshot?.lastUpdated {
                    Text("Оновлено: \(Self.timeFormatter.string(from: lastUpdated))")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                    Text("Повністю закрити програму (Quit)")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
