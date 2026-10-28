import Foundation

public final class YasnoAPIService {
    public static let shared = YasnoAPIService()
    
    private let session: URLSession
    private let cacheKey = "yasno_cached_snapshot"
    private let sharedFilePath = "/private/tmp/yasno_widget_shared_snapshot.json"
    private var rawRegionSchedulesCache: [Int: [String: Any]] = [:]
    
    public init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Fetch Schedule
    public func fetchSchedule(
        region: YasnoRegion,
        group: String
    ) async throws -> ScheduleSnapshot {
        // 1. Try modern blackout-service API
        let primaryUrlString = "https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/\(region.id)/dsos/\(region.dsoId)/planned-outages"
        var finalError: YasnoAPIError = .noData
        
        do {
            if let snapshot = try await fetchFromPrimaryAPI(urlString: primaryUrlString, region: region, group: group) {
                saveToCache(snapshot)
                return snapshot
            }
        } catch let apiError as YasnoAPIError {
            finalError = apiError
            print("[YasnoAPI] Primary API: \(apiError.localizedDescription). Trying fallback...")
        } catch {
            print("[YasnoAPI] Primary API error: \(error.localizedDescription). Trying fallback...")
        }
        
        // 2. Try legacy API fallback
        do {
            if let snapshot = try await fetchFromLegacyAPI(region: region, group: group) {
                saveToCache(snapshot)
                return snapshot
            }
        } catch {
            print("[YasnoAPI] Legacy API error: \(error.localizedDescription).")
        }
        
        // 3. If real (non-demo) cached data exists for this group/region, use it
        if let cached = loadFromCache(regionId: region.id, group: group), !cached.isFallbackMock {
            return cached
        }
        
        // 4. No live data and no cache: never show a fake demo schedule as if it were real!
        throw finalError
    }
    
    public enum YasnoAPIError: LocalizedError {
        case noData
        case groupNotFound(String)
        
        public var errorDescription: String? {
            switch self {
            case .noData:
                return "Не вдалося завантажити графік Yasno (немає з'єднання)"
            case .groupNotFound(let g):
                return "Черга \(g) відсутня у відповіді Yasno"
            }
        }
    }
    
    // MARK: - Address Search API (Streets, Houses, Group Resolution)
    public func searchStreets(region: YasnoRegion, query: String) async -> [YasnoAddressItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        let performQuery: (String) async -> [YasnoAddressItem] = { [weak self] q in
            guard let self = self,
                  let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/streets?regionId=\(region.id)&query=\(encoded)&dsoId=\(region.dsoId)") else {
                return []
            }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, response) = try? await self.session.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let items = self.parseAddressItems(from: data) {
                return items
            }
            return []
        }
        
        let initialResults = await performQuery(trimmed)
        if !initialResults.isEmpty {
            return initialResults
        }
        
        // Multi-word fallback: Yasno stores streets surname-first (e.g. "вул. Шевченка Тараса").
        // Search by individual meaningful words (longest word first, skipping prefixes like "вул", "просп").
        let stopWords: Set<String> = [
            "вул", "вулиця", "просп", "проспект", "бул", "бульвар", "пров", "провулок",
            "узвіз", "площа", "набережна", "шосе", "тупик", "алея", "тракт", "лінія", "street"
        ]
        let words = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !stopWords.contains($0.lowercased()) }
            .sorted { $0.count > $1.count }
        
        for word in words {
            let fallbackResults = await performQuery(word)
            if !fallbackResults.isEmpty {
                return fallbackResults
            }
        }
        
        return []
    }
    
    public func searchHouses(region: YasnoRegion, street: YasnoAddressItem, query: String) async -> [YasnoAddressItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryParam = trimmed.isEmpty ? "1" : trimmed
        
        if let encoded = queryParam.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/houses?regionId=\(region.id)&streetId=\(street.id)&query=\(encoded)&dsoId=\(region.dsoId)") {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let items = parseAddressItems(from: data) {
                return items
            }
        }
        return []
    }
    
    public func resolveGroup(region: YasnoRegion, street: YasnoAddressItem, house: YasnoAddressItem) async -> String? {
        var targetHouseId = house.id
        
        // If user typed a house number without clicking a resolved house item (id <= 0), look up its real houseId first
        if targetHouseId <= 0 {
            let cleanQuery = house.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let fetchedHouses = await searchHouses(region: region, street: street, query: cleanQuery)
            if let exactMatch = fetchedHouses.first(where: { $0.value.lowercased() == cleanQuery.lowercased() }) {
                targetHouseId = exactMatch.id
            } else if let firstMatch = fetchedHouses.first {
                targetHouseId = firstMatch.id
            } else {
                return nil
            }
        }
        
        guard let url = URL(string: "https://app.yasno.ua/api/blackout-service/public/shutdowns/addresses/v2/group?regionId=\(region.id)&streetId=\(street.id)&houseId=\(targetHouseId)&dsoId=\(region.dsoId)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let (data, response) = try? await session.data(for: request),
           let http = response as? HTTPURLResponse, http.statusCode == 200,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let groupVal = dict["group"].flatMap { $0 is NSNull ? nil : "\($0)" }
            let subgroupVal = dict["subgroup"].flatMap { $0 is NSNull ? nil : "\($0)" }
            if let g = groupVal, !g.isEmpty {
                if g.contains(".") {
                    return g
                }
                if let s = subgroupVal, !s.isEmpty {
                    return "\(g).\(s)"
                }
                return "\(g).1"
            }
        }
        return nil
    }
    
    // MARK: - Infer Outage Group from Live Sensor (Telegram title, hints, transitions)
    public func fetchAllGroupsSchedules(region: YasnoRegion) async -> [String: [OutageSlot]] {
        var rawDict = rawRegionSchedulesCache[region.id]
        if rawDict == nil {
            let primaryUrlString = "https://app.yasno.ua/api/blackout-service/public/shutdowns/regions/\(region.id)/dsos/\(region.dsoId)/planned-outages"
            if let url = URL(string: primaryUrlString) {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (data, response) = try? await session.data(for: request),
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.rawRegionSchedulesCache[region.id] = jsonObject
                    rawDict = jsonObject
                }
            }
        }
        guard let dict = rawDict else { return [:] }
        var result: [String: [OutageSlot]] = [:]
        for (groupKey, val) in dict {
            if let gDict = val as? [String: Any],
               let todayDict = gDict["today"] as? [String: Any] {
                let slots = parseSlotsFromDayDict(todayDict).filter { $0.type == .off }
                result[groupKey] = slots
            }
        }
        return result
    }
    
    public func inferGroupFromSensor(region: YasnoRegion, status: LiveSensorStatus) async -> String? {
        if let explicit = status.detectedGroup, !explicit.isEmpty {
            return explicit
        }
        
        let allGroups = await fetchAllGroupsSchedules(region: region)
        
        var groupScores: [String: Int] = [:]
        for (gName, plannedOffSlots) in allGroups {
            var score = 0
            
            // Match against planned outage hints from messages
            for hint in status.plannedHints where hint.type == .off {
                for slot in plannedOffSlots {
                    if abs(slot.startMinutes - hint.startMinutes) <= 30 && abs(slot.endMinutes - hint.endMinutes) <= 30 {
                        score += 25
                    } else if abs(slot.endMinutes - hint.endMinutes) <= 30 {
                        score += 15
                    } else if (max(slot.startMinutes, hint.startMinutes) < min(slot.endMinutes, hint.endMinutes)) {
                        score += 10
                    }
                }
            }
            
            // Match against actual power transitions
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = ScheduleCalculator.kyivTimeZone
            let now = Date()
            let todayDay = cal.component(.day, from: now)
            
            for (idx, tr) in status.transitions.enumerated() {
                guard cal.component(.day, from: tr.timestamp) == todayDay else { continue }
                if !tr.isPowerOn {
                    let offMin = ScheduleCalculator.kyivMinuteOfDay(for: tr.timestamp)
                    let onMin: Int
                    if idx + 1 < status.transitions.count {
                        onMin = ScheduleCalculator.kyivMinuteOfDay(for: status.transitions[idx + 1].timestamp)
                    } else {
                        onMin = ScheduleCalculator.kyivMinuteOfDay(for: now)
                    }
                    for slot in plannedOffSlots {
                        if (max(slot.startMinutes, offMin) < min(slot.endMinutes, onMin)) {
                            score += 5
                        }
                    }
                }
            }
            
            if score > 0 {
                groupScores[gName] = score
            }
        }
        
        let topScore = groupScores.values.max() ?? 0
        let bestScheduleGroups = groupScores.filter { $0.value == topScore && topScore > 0 }.map { $0.key }
        
        // Match street name in channel title if available
        if let rawTitle = status.channelTitle, !rawTitle.isEmpty {
            var streetQuery = rawTitle
            var houseQuery: String? = nil
            
            let houseRegex = try? NSRegularExpression(pattern: #"(?:буд\.?|будинок|д\.?|№)?\s*([0-9]+[а-яіїєa-z\/\-]*)\b"#, options: [.caseInsensitive])
            if let match = houseRegex?.firstMatch(in: rawTitle, range: NSRange(rawTitle.startIndex..., in: rawTitle)),
               let range = Range(match.range(at: 1), in: rawTitle) {
                houseQuery = String(rawTitle[range])
                if let fullMatchRange = Range(match.range, in: rawTitle) {
                    streetQuery.removeSubrange(fullMatchRange)
                }
            }
            
            streetQuery = streetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ",.-/"))
            
            let streets = await searchStreets(region: region, query: streetQuery)
            if let street = streets.first {
                let houseToSearch = houseQuery ?? "1"
                let houses = await searchHouses(region: region, street: street, query: houseToSearch)
                let targetHouse = houses.first(where: { $0.value.lowercased() == houseToSearch.lowercased() }) ?? houses.first
                if let house = targetHouse, let resolved = await resolveGroup(region: region, street: street, house: house) {
                    if bestScheduleGroups.isEmpty || bestScheduleGroups.contains(resolved) {
                        return resolved
                    }
                    return resolved
                }
            }
        }
        
        if let first = bestScheduleGroups.first {
            return first
        }
        
        return nil
    }
    
    private func parseAddressItems(from data: Data) -> [YasnoAddressItem]? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        var items: [YasnoAddressItem] = []
        for obj in arr {
            let id = (obj["id"] as? Int) ?? Int((obj["id"] as? String) ?? "0") ?? 0
            let val = (obj["value"] as? String) ?? (obj["name"] as? String) ?? ""
            if id > 0 && !val.isEmpty {
                items.append(YasnoAddressItem(id: id, value: val))
            }
        }
        return items
    }
    
    // MARK: - Primary API Parsing
    private func fetchFromPrimaryAPI(urlString: String, region: YasnoRegion, group: String) async throws -> ScheduleSnapshot? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        self.rawRegionSchedulesCache[region.id] = jsonObject
        
        let allDiscoveredGroups = Array(jsonObject.keys).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        
        var resolvedGroupKey = group
        var targetGroupDict: [String: Any]? = jsonObject[group] as? [String: Any]
        if targetGroupDict == nil {
            if let exactKey = allDiscoveredGroups.first(where: { $0.lowercased() == group.lowercased() }) {
                resolvedGroupKey = exactKey
                targetGroupDict = jsonObject[exactKey] as? [String: Any]
            } else if !group.contains("."),
                      let baseKey = allDiscoveredGroups.first(where: { ($0.split(separator: ".").first.map(String.init) ?? $0) == group }) {
                // Only for groups entered without a subgroup (e.g. "3" -> "3.1").
                // Never substitute a DIFFERENT subgroup (6.2 -> 6.1) or a random first group: that would show someone else's schedule!
                resolvedGroupKey = baseKey
                targetGroupDict = jsonObject[baseKey] as? [String: Any]
            }
        }
        
        guard let groupDict = targetGroupDict else {
            throw YasnoAPIError.groupNotFound(group)
        }
        
        let now = Date()
        let todayDict = groupDict["today"] as? [String: Any]
        let tomorrowDict = groupDict["tomorrow"] as? [String: Any]
        
        let todaySlots = parseSlotsFromDayDict(todayDict)
        let tomorrowSlots = parseSlotsFromDayDict(tomorrowDict)
        let todayStatus = parseStatusFromDayDict(todayDict)
        let tomorrowStatus = parseStatusFromDayDict(tomorrowDict)
        
        let filledToday = todaySlots.isEmpty && todayStatus != .scheduleApplies
            ? []
            : ScheduleCalculator.fillGapsWithPowerOn(slots: todaySlots)
        let filledTomorrow = tomorrowSlots.isEmpty && tomorrowStatus != .scheduleApplies
            ? []
            : ScheduleCalculator.fillGapsWithPowerOn(slots: tomorrowSlots)
        
        let currentMinute = ScheduleCalculator.kyivMinuteOfDay(for: now)
        let currentStatus: OutageType = todayStatus.isEmergency
            ? .off
            : ScheduleCalculator.calculateCurrentStatus(slots: filledToday, currentMinute: currentMinute)
        
        return ScheduleSnapshot(
            currentStatus: currentStatus,
            currentMinuteOfDay: currentMinute,
            today: DaySchedule(date: now, isToday: true, slots: filledToday, status: todayStatus),
            tomorrow: DaySchedule(date: ScheduleCalculator.kyivStartOfNextDay(for: now), isToday: false, slots: filledTomorrow, status: tomorrowStatus),
            lastUpdated: now,
            regionId: region.id,
            dsoId: region.dsoId,
            group: resolvedGroupKey,
            isFallbackMock: false,
            discoveredGroups: allDiscoveredGroups
        )
    }
    
    private func parseStatusFromDayDict(_ dayDict: [String: Any]?) -> DayScheduleStatus {
        guard let rawStatus = (dayDict?["status"] as? String)?.lowercased() else {
            return .scheduleApplies
        }
        if rawStatus.contains("emergency") {
            return .emergencyShutdowns
        } else if rawStatus.contains("waiting") {
            return .waitingForSchedule
        }
        return .scheduleApplies
    }
    
    private func parseSlotsFromDayDict(_ dayDict: [String: Any]?) -> [OutageSlot] {
        guard let dayDict = dayDict, let slotsArray = dayDict["slots"] as? [[String: Any]] else {
            return []
        }
        
        var parsed: [OutageSlot] = []
        for item in slotsArray {
            let start = item["start"] as? Int ?? 0
            let end = item["end"] as? Int ?? 0
            let rawType = (item["type"] as? String ?? "").lowercased()
            
            let outageType: OutageType
            if rawType.contains("definite") || rawType.contains("off") {
                outageType = .off
            } else if rawType.contains("possible") || rawType.contains("probable") {
                outageType = .possible
            } else {
                outageType = .on
            }
            
            if end > start {
                parsed.append(OutageSlot(startMinutes: start, endMinutes: end, type: outageType))
            }
        }
        return parsed
    }
    
    // MARK: - Legacy API Parsing
    private func fetchFromLegacyAPI(region: YasnoRegion, group: String) async throws -> ScheduleSnapshot? {
        guard let url = URL(string: "https://api.yasno.com.ua/api/v1/pages/home/schedule-turn-off-electricity") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let components = root["components"] as? [[String: Any]] else {
            return nil
        }
        
        let scheduleComp = components.first { ($0["template_name"] as? String) == "electricity-outages-daily-schedule" }
        guard let dailySchedule = scheduleComp?["dailySchedule"] as? [String: Any] else {
            return nil
        }
        
        let regionKey = region.id == 4 ? "dnipro" : "kiev"
        guard let regionData = dailySchedule[regionKey] as? [String: Any] else {
            return nil
        }
        
        let now = Date()
        // If the requested group is absent in the legacy feed, don't pretend there are no outages
        guard let todaySlots = parseLegacySlots(regionData["today"] as? [String: Any], group: group) else {
            return nil
        }
        let tomorrowSlots = parseLegacySlots(regionData["tomorrow"] as? [String: Any], group: group) ?? []
        
        let filledToday = ScheduleCalculator.fillGapsWithPowerOn(slots: todaySlots)
        let filledTomorrow = ScheduleCalculator.fillGapsWithPowerOn(slots: tomorrowSlots)
        
        let currentMinute = ScheduleCalculator.kyivMinuteOfDay(for: now)
        let currentStatus = ScheduleCalculator.calculateCurrentStatus(slots: filledToday, currentMinute: currentMinute)
        
        return ScheduleSnapshot(
            currentStatus: currentStatus,
            currentMinuteOfDay: currentMinute,
            today: DaySchedule(date: now, isToday: true, slots: filledToday, status: .scheduleApplies),
            tomorrow: DaySchedule(date: ScheduleCalculator.kyivStartOfNextDay(for: now), isToday: false, slots: filledTomorrow, status: .scheduleApplies),
            lastUpdated: now,
            regionId: region.id,
            dsoId: region.dsoId,
            group: group,
            isFallbackMock: false
        )
    }
    
    private func parseLegacySlots(_ dayDict: [String: Any]?, group: String) -> [OutageSlot]? {
        guard let dayDict = dayDict,
              let groups = dayDict["groups"] as? [String: Any],
              let slotItems = groups[group] as? [[String: Any]] else {
            return nil
        }
        
        var result: [OutageSlot] = []
        for item in slotItems {
            let startHours = (item["start"] as? NSNumber)?.doubleValue ?? 0
            let endHours = (item["end"] as? NSNumber)?.doubleValue ?? 0
            let typeStr = (item["type"] as? String ?? "").lowercased()
            
            let startMin = Int(startHours * 60)
            let endMin = Int(endHours * 60)
            
            let outageType: OutageType
            if typeStr.contains("definite") {
                outageType = .off
            } else if typeStr.contains("possible") {
                outageType = .possible
            } else {
                outageType = .on
            }
            
            if endMin > startMin {
                result.append(OutageSlot(startMinutes: startMin, endMinutes: endMin, type: outageType))
            }
        }
        return result
    }
    
    // MARK: - Cache Helpers (App Group + Shared File + UserDefaults for WidgetKit)
    private func saveToCache(_ snapshot: ScheduleSnapshot) {
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        let specificKey = "\(cacheKey)_\(snapshot.regionId)_\(snapshot.group)"
        
        // 1. Save to App Group Container
        if let dir = SharedStateStore.groupContainerURL {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? encoded.write(to: dir.appendingPathComponent("\(specificKey).json"), options: .atomic)
            try? encoded.write(to: dir.appendingPathComponent("yasno_latest_snapshot.json"), options: .atomic)
        }
        
        // 2. Save to UserDefaults (App Group & standard)
        let suites: [UserDefaults?] = [
            UserDefaults(suiteName: SharedStateStore.appGroupId),
            UserDefaults(suiteName: "ua.yasno.mac.widget"),
            UserDefaults.standard
        ]
        for suite in suites {
            suite?.set(encoded, forKey: specificKey)
            suite?.set(encoded, forKey: cacheKey)
        }
        
        // 3. Save to /private/tmp/
        try? encoded.write(to: URL(fileURLWithPath: sharedFilePath), options: .atomic)
        try? encoded.write(to: URL(fileURLWithPath: "/private/tmp/\(specificKey).json"), options: .atomic)
    }
    
    public func loadFromCache(regionId: Int? = nil, group: String? = nil) -> ScheduleSnapshot? {
        if let r = regionId, let g = group {
            let specificKey = "\(cacheKey)_\(r)_\(g)"
            
            // 1. Check App Group specific file
            if let dir = SharedStateStore.groupContainerURL,
               let data = try? Data(contentsOf: dir.appendingPathComponent("\(specificKey).json")),
               let snap = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) {
                return snap
            }
            
            // 2. Check /private/tmp/ specific file
            if let data = try? Data(contentsOf: URL(fileURLWithPath: "/private/tmp/\(specificKey).json")),
               let snap = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) {
                return snap
            }
            
            // 3. Check UserDefaults suites for specificKey
            let suites: [UserDefaults?] = [
                UserDefaults(suiteName: SharedStateStore.appGroupId),
                UserDefaults(suiteName: "ua.yasno.mac.widget"),
                UserDefaults.standard
            ]
            for suite in suites {
                if let data = suite?.data(forKey: specificKey),
                   let snap = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) {
                    return snap
                }
            }
        }
        
        // Fallback: latest snapshot if it matches regionId/group (or if regionId/group not specified)
        if let dir = SharedStateStore.groupContainerURL,
           let data = try? Data(contentsOf: dir.appendingPathComponent("yasno_latest_snapshot.json")),
           let snap = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) {
            if regionId == nil || (snap.regionId == regionId && snap.group == group) {
                return snap
            }
        }
        
        if let sharedData = try? Data(contentsOf: URL(fileURLWithPath: sharedFilePath)),
           let sharedSnapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: sharedData) {
            if regionId == nil || (sharedSnapshot.regionId == regionId && sharedSnapshot.group == group) {
                return sharedSnapshot
            }
        }
        
        return nil
    }
}
