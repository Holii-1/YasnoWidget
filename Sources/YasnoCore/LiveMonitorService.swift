import Foundation

public final class LiveMonitorService {
    public static let shared = LiveMonitorService()
    
    private let session: URLSession
    
    private static let kyivTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        return formatter
    }()
    
    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Main Entry Point
    public func checkStatus(type: LiveSensorType, target: String?) async -> LiveSensorStatus? {
        guard type != .disabled else { return nil }
        let rawTarget = (target ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTarget.isEmpty else {
            return LiveSensorStatus(
                source: type,
                state: .error,
                statusText: "\(type.titleUk): Не вказано ключ або канал",
                detailText: "Введіть дані для підключення в налаштуваннях"
            )
        }
        
        switch type {
        case .disabled:
            return nil
        case .svitlobot:
            return await checkSvitlobot(rawTarget: rawTarget)
        case .healthchecks:
            return await checkHealthchecks(rawTarget: rawTarget)
        }
    }
    
    // MARK: - 1. SvitloBot Integration (Telegram Channel or channel_key)
    public func checkSvitlobot(rawTarget: String) async -> LiveSensorStatus {
        let cleaned = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Case A: Direct api.svitlobot.in.ua URL
        if cleaned.lowercased().contains("api.svitlobot.in.ua") {
            return await fetchSvitlobotAPI(urlOrKey: cleaned)
        }
        
        // Extract Telegram channel slug if it looks like @channel, t.me/channel, or channel_slug
        let slug = Self.extractTelegramChannelSlug(from: cleaned)
        if !slug.isEmpty {
            let tgURLString = "https://t.me/s/\(slug)"
            if let url = URL(string: tgURLString) {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                request.setValue("uk-UA,uk;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
                
                if let (data, response) = try? await session.data(for: request),
                   let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode),
                   let html = String(data: data, encoding: .utf8) {
                    
                    let parsed = Self.parseSvitlobotTelegramHTML(html, channelName: slug)
                    if parsed.state != .error {
                        return parsed
                    }
                    // If Telegram channel didn't match and input had no '@' or 't.me', try SvitloBot API key fallback
                    if !cleaned.contains("@") && !cleaned.lowercased().contains("t.me") {
                        let apiResult = await fetchSvitlobotAPI(urlOrKey: cleaned)
                        if apiResult.state != .error {
                            return apiResult
                        }
                    }
                    return parsed
                }
            }
        }
        
        return await fetchSvitlobotAPI(urlOrKey: cleaned)
    }
    
    private func fetchSvitlobotAPI(urlOrKey: String) async -> LiveSensorStatus {
        let urlString: String
        if urlOrKey.lowercased().hasPrefix("http://") || urlOrKey.lowercased().hasPrefix("https://") {
            urlString = urlOrKey
        } else {
            let encoded = urlOrKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlOrKey
            urlString = "https://api.svitlobot.in.ua/status?channel_key=\(encoded)"
        }
        
        guard let url = URL(string: urlString) else {
            return LiveSensorStatus(
                source: .svitlobot,
                state: .error,
                statusText: "СвітлоБот: Невірний формат каналу або ключа",
                detailText: "Вкажіть @канал_будинку або ключ СвітлоБота"
            )
        }
        
        var request = URLRequest(url: url)
        request.setValue("YasnoWidget-macOS/2.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let body = String(data: data, encoding: .utf8) else {
                return LiveSensorStatus(
                    source: .svitlobot,
                    state: .error,
                    statusText: "СвітлоБот: Канал або ключ не знайдено",
                    detailText: "Перевірте назву публічного каналу (@...)"
                )
            }
            return Self.parseSvitlobotStatusResponse(body)
        } catch {
            return LiveSensorStatus(
                source: .svitlobot,
                state: .error,
                statusText: "СвітлоБот: Немає зв'язку із сервером",
                detailText: error.localizedDescription
            )
        }
    }
    
    public static func extractTelegramChannelSlug(from input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "t.me/s/", options: .caseInsensitive) {
            s = String(s[range.upperBound...])
        } else if let range = s.range(of: "t.me/", options: .caseInsensitive) {
            s = String(s[range.upperBound...])
        } else if let range = s.range(of: "telegram.me/", options: .caseInsensitive) {
            s = String(s[range.upperBound...])
        }
        if s.hasPrefix("@") {
            s.removeFirst()
        }
        if let slashIdx = s.firstIndex(of: "/") {
            s = String(s[..<slashIdx])
        }
        if let queryIdx = s.firstIndex(of: "?") {
            s = String(s[..<queryIdx])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public static func parseSvitlobotTelegramHTML(
        _ html: String,
        channelName: String,
        now: Date = Date()
    ) -> LiveSensorStatus {
        let blocks = html.components(separatedBy: "tgme_widget_message_wrap")
        guard blocks.count > 1 else {
            return LiveSensorStatus(
                source: .svitlobot,
                state: .error,
                statusText: "СвітлоБот: Канал @\(channelName) порожній",
                detailText: "Переконайтеся, що канал публічний (t.me/s/\(channelName))",
                checkedAt: now
            )
        }
        
        // Extract channel metadata texts (description, title, pinned message)
        var metadataTexts = extractChannelMetadataTexts(from: html)
        let cleanTitle = extractCleanChannelTitle(from: html)
        if let title = cleanTitle, !title.isEmpty {
            metadataTexts.append(title)
        }
        
        // Parse ALL power transition messages in chronological order (oldest -> newest)
        // and collect any planned outage schedule hints mentioned in messages
        var transitions: [PowerTransitionEvent] = []
        var plannedHints: [OutageSlot] = []
        
        for block in blocks.dropFirst() {
            let textPart: String
            if let textRange = block.range(of: "tgme_widget_message_text") {
                let afterClass = String(block[textRange.upperBound...])
                if let endDiv = afterClass.range(of: "</div>") {
                    textPart = String(afterClass[..<endDiv.lowerBound])
                } else {
                    textPart = afterClass
                }
            } else {
                textPart = block
            }
            
            let rawText = stripHTML(textPart)
            if metadataTexts.count < 25 {
                metadataTexts.append(rawText)
            }
            let cleanText = rawText.lowercased()
            let baseDate = extractTelegramMessageDate(from: block)
            let eventDate = refineDateWithExplicitTimeInText(baseDate: baseDate, text: rawText)
            
            let messageHints = extractPlannedHintsFromMessage(rawText: rawText, messageDate: eventDate ?? baseDate, now: now)
            plannedHints.append(contentsOf: messageHints)
            
            let isPowerOn = cleanText.contains("світло з'явилося")
                || cleanText.contains("світло з’явилося")
                || cleanText.contains("світло зʼявилося")
                || cleanText.contains("світло є")
                || cleanText.contains("живлення відновлено")
                || cleanText.contains("електропостачання відновлено")
                || cleanText.contains("світло увімкнули")
                || cleanText.contains("увімкнули світло")
                || cleanText.contains("🟢")
            
            let isPowerOff = cleanText.contains("світло зникло")
                || cleanText.contains("світла немає")
                || cleanText.contains("світла нема")
                || cleanText.contains("світло вимкнули")
                || cleanText.contains("вимкнули світло")
                || cleanText.contains("живлення відсутнє")
                || cleanText.contains("електропостачання відсутнє")
                || cleanText.contains("🔴")
                || cleanText.contains("⚫️")
            
            var messageStateOn: Bool? = nil
            if isPowerOn && !isPowerOff {
                messageStateOn = true
            } else if isPowerOff && !isPowerOn {
                messageStateOn = false
            } else if isPowerOn && isPowerOff {
                let onIdx = cleanText.range(of: "з'явилося")?.lowerBound
                    ?? cleanText.range(of: "з’явилося")?.lowerBound
                    ?? cleanText.range(of: "🟢")?.lowerBound
                let offIdx = cleanText.range(of: "зникло")?.lowerBound
                    ?? cleanText.range(of: "🔴")?.lowerBound
                if let onIdx = onIdx, let offIdx = offIdx {
                    messageStateOn = (onIdx < offIdx)
                }
            }
            
            if let isOn = messageStateOn, let date = eventDate {
                transitions.append(PowerTransitionEvent(timestamp: date, isPowerOn: isOn))
            } else if let isOn = messageStateOn {
                transitions.append(PowerTransitionEvent(timestamp: now, isPowerOn: isOn))
            }
        }
        
        let detectedGroup = detectGroup(from: metadataTexts, channelSlug: channelName)
        
        var uniquePlannedHints: [OutageSlot] = []
        for hint in plannedHints {
            if !uniquePlannedHints.contains(where: { $0.startMinutes == hint.startMinutes && $0.endMinutes == hint.endMinutes && $0.type == hint.type }) {
                uniquePlannedHints.append(hint)
            }
        }
        
        guard let latest = transitions.last else {
            return LiveSensorStatus(
                source: .svitlobot,
                state: .error,
                statusText: "СвітлоБот: Статус не знайдено в @\(channelName)",
                detailText: "У каналі немає повідомлень про стан світла",
                checkedAt: now,
                detectedGroup: detectedGroup,
                channelTitle: cleanTitle,
                plannedHints: uniquePlannedHints
            )
        }
        
        if latest.isPowerOn {
            let timeDetail = formatEventDetail(prefix: "Увімкнули", eventDate: latest.timestamp, channelName: channelName, now: now)
            return LiveSensorStatus(
                source: .svitlobot,
                state: .online,
                statusText: "СвітлоБот: Світло Є",
                detailText: timeDetail,
                eventTimestamp: latest.timestamp,
                checkedAt: now,
                transitions: transitions,
                detectedGroup: detectedGroup,
                channelTitle: cleanTitle,
                plannedHints: uniquePlannedHints
            )
        } else {
            let timeDetail = formatEventDetail(prefix: "Вимкнули", eventDate: latest.timestamp, channelName: channelName, now: now)
            return LiveSensorStatus(
                source: .svitlobot,
                state: .offline,
                statusText: "СвітлоБот: Світла НЕМАЄ",
                detailText: timeDetail,
                eventTimestamp: latest.timestamp,
                checkedAt: now,
                transitions: transitions,
                detectedGroup: detectedGroup,
                channelTitle: cleanTitle,
                plannedHints: uniquePlannedHints
            )
        }
    }
    
    public static func parseSvitlobotStatusResponse(_ body: String, now: Date = Date()) -> LiveSensorStatus {
        let stripped = stripHTML(body)
        let lower = stripped.lowercased().replacingOccurrences(of: " ", with: "")
        
        var detectedGroup: String? = nil
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            detectedGroup = detectGroup(from: [stripped], channelSlug: "", jsonDict: json)
        } else {
            detectedGroup = findGroupInText(stripped)
        }
        
        // IMPORTANT: check explicit OFF markers first — `"is_online":false` contains the substring "online"!
        let isOff = lower.contains("світланемає") || lower.contains("світлозникло")
            || lower.contains("\"status\":\"down\"") || lower.contains("\"status\":\"offline\"")
            || lower.contains("\"is_online\":false") || lower.contains("\"online\":false")
            || lower.contains("🔴")
        let isOn = !isOff && (lower.contains("світлоє") || lower.contains("світлоз'явилося") || lower.contains("світлоз’явилося")
            || lower.contains("\"status\":\"up\"") || lower.contains("\"status\":\"online\"")
            || lower.contains("\"is_online\":true") || lower.contains("\"online\":true")
            || lower.contains("🟢"))
        
        if isOn {
            return LiveSensorStatus(
                source: .svitlobot,
                state: .online,
                statusText: "СвітлоБот: Світло Є",
                detailText: "Датчик СвітлоБота активний (Онлайн)",
                eventTimestamp: now,
                checkedAt: now,
                detectedGroup: detectedGroup
            )
        }
        
        if isOff {
            return LiveSensorStatus(
                source: .svitlobot,
                state: .offline,
                statusText: "СвітлоБот: Світла НЕМАЄ",
                detailText: "Датчик СвітлоБота офлайн (Немає живлення)",
                eventTimestamp: now,
                checkedAt: now,
                detectedGroup: detectedGroup
            )
        }
        
        return LiveSensorStatus(
            source: .svitlobot,
            state: .error,
            statusText: "СвітлоБот: Невідома відповідь датчика",
            detailText: "Перевірте @канал або channel_key",
            checkedAt: now,
            detectedGroup: detectedGroup
        )
    }
    
    // MARK: - 2. Healthchecks.io Integration (API Key / Badge URL / Check URL)
    public func checkHealthchecks(rawTarget: String) async -> LiveSensorStatus {
        let cleaned = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // CRITICAL SAFEGUARD: Never GET hc-ping.com, as that would send a fake heartbeat ping!
        if cleaned.lowercased().contains("hc-ping.com") || cleaned.lowercased().contains("/ping/") {
            return LiveSensorStatus(
                source: .healthchecks,
                state: .error,
                statusText: "Healthchecks: Це URL для ESP32 (hc-ping.com)!",
                detailText: "Вставте Read-Only API Key або Badge URL з кабінету Healthchecks.io"
            )
        }
        
        // Case A: Badge URL (https://healthchecks.io/b/... or /badge/...)
        if cleaned.lowercased().contains("/b/") || cleaned.lowercased().contains("/badge/") {
            var badgeURLStr = cleaned
            if badgeURLStr.hasSuffix(".svg") {
                badgeURLStr = String(badgeURLStr.dropLast(4)) + ".json"
            } else if badgeURLStr.hasSuffix(".shields") {
                badgeURLStr = String(badgeURLStr.dropLast(8)) + ".json"
            } else if !badgeURLStr.hasSuffix(".json") {
                badgeURLStr += ".json"
            }
            
            guard let url = URL(string: badgeURLStr) else {
                return LiveSensorStatus(
                    source: .healthchecks,
                    state: .error,
                    statusText: "Healthchecks: Невірний Badge URL",
                    detailText: nil
                )
            }
            
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    return LiveSensorStatus(
                        source: .healthchecks,
                        state: .error,
                        statusText: "Healthchecks: Помилка доступу до Badge URL",
                        detailText: "Перевірте посилання у розділі Badges"
                    )
                }
                return Self.parseHealthchecksJSON(data)
            } catch {
                return LiveSensorStatus(
                    source: .healthchecks,
                    state: .error,
                    statusText: "Healthchecks: Помилка мережі",
                    detailText: error.localizedDescription
                )
            }
        }
        
        // Case B: Full API URL or Read-Only API Key (optionally "API_KEY:CHECK_ID_OR_NAME")
        let apiKey: String
        let filterCheck: String?
        let requestURL: URL?
        
        if cleaned.lowercased().hasPrefix("http://") || cleaned.lowercased().hasPrefix("https://") {
            requestURL = URL(string: cleaned)
            apiKey = ""
            filterCheck = nil
        } else {
            let parts = cleaned.split(separator: ":", maxSplits: 1).map(String.init)
            apiKey = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            filterCheck = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            requestURL = URL(string: "https://healthchecks.io/api/v3/checks/")
        }
        
        guard let url = requestURL else {
            return LiveSensorStatus(
                source: .healthchecks,
                state: .error,
                statusText: "Healthchecks: Невірний ключ або URL",
                detailText: nil
            )
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return LiveSensorStatus(
                    source: .healthchecks,
                    state: .error,
                    statusText: "Healthchecks: Немає відповіді сервера",
                    detailText: nil
                )
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return LiveSensorStatus(
                    source: .healthchecks,
                    state: .error,
                    statusText: "Healthchecks: Невірний API Key (401)",
                    detailText: "Скопіюйте Read-Only API Key у Settings → API"
                )
            }
            guard (200...299).contains(http.statusCode) else {
                return LiveSensorStatus(
                    source: .healthchecks,
                    state: .error,
                    statusText: "Healthchecks: Помилка HTTP \(http.statusCode)",
                    detailText: nil
                )
            }
            
            var status = Self.parseHealthchecksJSON(data, filterCheck: filterCheck)
            
            // Also fetch flips history (/api/v3/checks/<uuid_or_unique_key>/flips/) so today's timeline bar & slots reflect actual history!
            if !apiKey.isEmpty,
               let checkId = Self.extractTargetCheckIdentifier(from: data, filterCheck: filterCheck),
               let flipsURL = URL(string: "https://healthchecks.io/api/v3/checks/\(checkId)/flips/?seconds=172800") {
                var flipsReq = URLRequest(url: flipsURL)
                flipsReq.setValue("application/json", forHTTPHeaderField: "Accept")
                flipsReq.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
                if let (flipsData, flipsResp) = try? await session.data(for: flipsReq),
                   let flipsHttp = flipsResp as? HTTPURLResponse,
                   (200...299).contains(flipsHttp.statusCode) {
                    var flips = Self.parseHealthchecksFlipsJSON(flipsData)
                    // If /flips/ succeeded and returned [] (0 state changes in 48h), anchor the state 24h ago
                    if flips.isEmpty && (status.state == .online || status.state == .offline) {
                        flips = [
                            PowerTransitionEvent(
                                timestamp: Date().addingTimeInterval(-86400),
                                isPowerOn: status.state == .online
                            )
                        ]
                    }
                    if !flips.isEmpty {
                        status = LiveSensorStatus(
                            source: status.source,
                            state: status.state,
                            statusText: status.statusText,
                            detailText: status.detailText,
                            eventTimestamp: status.eventTimestamp ?? flips.last?.timestamp,
                            checkedAt: status.checkedAt,
                            transitions: flips,
                            detectedGroup: status.detectedGroup
                        )
                    }
                }
            }
            
            return status
        } catch {
            return LiveSensorStatus(
                source: .healthchecks,
                state: .error,
                statusText: "Healthchecks: Помилка з'єднання",
                detailText: error.localizedDescription
            )
        }
    }
    
    public static func parseHealthchecksJSON(
        _ data: Data,
        filterCheck: String? = nil,
        now: Date = Date()
    ) -> LiveSensorStatus {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LiveSensorStatus(
                source: .healthchecks,
                state: .error,
                statusText: "Healthchecks: Невірний формат JSON",
                detailText: nil,
                checkedAt: now
            )
        }
        
        // 1. If JSON has "checks" array (Management API /api/v3/checks/)
        if let checks = json["checks"] as? [[String: Any]] {
            guard !checks.isEmpty else {
                return LiveSensorStatus(
                    source: .healthchecks,
                    state: .error,
                    statusText: "Healthchecks: У проєкті немає жодного Check",
                    detailText: "Створіть Check для ESP32 у Healthchecks.io",
                    checkedAt: now
                )
            }
            
            let targetCheck: [String: Any]
            if let filter = filterCheck?.lowercased(), !filter.isEmpty {
                targetCheck = checks.first(where: { chk in
                    let name = (chk["name"] as? String)?.lowercased() ?? ""
                    let slug = (chk["slug"] as? String)?.lowercased() ?? ""
                    let uuid = (chk["uuid"] as? String)?.lowercased() ?? ""
                    let uniqueKey = (chk["unique_key"] as? String)?.lowercased() ?? ""
                    return name.contains(filter) || slug == filter || uuid.hasPrefix(filter) || uniqueKey.hasPrefix(filter)
                }) ?? checks[0]
            } else {
                targetCheck = checks[0]
            }
            
            return buildStatusFromCheckObject(targetCheck, now: now)
        }
        
        // 2. Single check object or Badge JSON {"status": "up" | "down" | "late" | "grace", ...}
        return buildStatusFromCheckObject(json, now: now)
    }
    
    public static func extractTargetCheckIdentifier(from data: Data, filterCheck: String? = nil) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let targetObj: [String: Any]
        if let checks = json["checks"] as? [[String: Any]], !checks.isEmpty {
            if let filter = filterCheck?.lowercased(), !filter.isEmpty {
                targetObj = checks.first(where: { chk in
                    let name = (chk["name"] as? String)?.lowercased() ?? ""
                    let slug = (chk["slug"] as? String)?.lowercased() ?? ""
                    let uuid = (chk["uuid"] as? String)?.lowercased() ?? ""
                    let uniqueKey = (chk["unique_key"] as? String)?.lowercased() ?? ""
                    return name.contains(filter) || slug == filter || uuid.hasPrefix(filter) || uniqueKey.hasPrefix(filter)
                }) ?? checks[0]
            } else {
                targetObj = checks[0]
            }
        } else {
            targetObj = json
        }
        return (targetObj["unique_key"] as? String) ?? (targetObj["uuid"] as? String)
    }
    
    public static func parseHealthchecksFlipsJSON(_ data: Data) -> [PowerTransitionEvent] {
        let rawList: [[String: Any]]
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let flips = dict["flips"] as? [[String: Any]] {
            rawList = flips
        } else if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            rawList = arr
        } else {
            return []
        }
        
        var events: [PowerTransitionEvent] = []
        for item in rawList {
            guard let tsStr = item["timestamp"] as? String,
                  let date = parseISODate(tsStr) else { continue }
            let isUp: Bool
            if let upInt = item["up"] as? Int {
                isUp = (upInt == 1)
            } else if let upBool = item["up"] as? Bool {
                isUp = upBool
            } else if let upStr = item["up"] as? String {
                isUp = (upStr == "1" || upStr.lowercased() == "true" || upStr.lowercased() == "up")
            } else {
                continue
            }
            events.append(PowerTransitionEvent(timestamp: date, isPowerOn: isUp))
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }
    
    private static func buildStatusFromCheckObject(_ obj: [String: Any], now: Date) -> LiveSensorStatus {
        let rawStatus = (obj["status"] as? String)?.lowercased() ?? "unknown"
        let checkName = (obj["name"] as? String) ?? (obj["label"] as? String)
        let slug = (obj["slug"] as? String) ?? ""
        let tags = (obj["tags"] as? String) ?? ""
        let desc = (obj["desc"] as? String) ?? ""
        let detectedGroup = detectGroup(from: [checkName ?? "", tags, desc], channelSlug: slug)
        
        let lastPingStr = obj["last_ping"] as? String
        let lastPingDate = parseISODate(lastPingStr)
        
        let pingAgeInfo: String
        if let pingDate = lastPingDate {
            let secondsAgo = max(0, Int(now.timeIntervalSince(pingDate)))
            let timeStr = kyivTimeFormatter.string(from: pingDate)
            if secondsAgo < 90 {
                pingAgeInfo = "Пінг \(secondsAgo) сек тому (о \(timeStr))"
            } else if secondsAgo < 3600 {
                pingAgeInfo = "Останній пінг \(secondsAgo / 60) хв тому (о \(timeStr))"
            } else {
                let h = secondsAgo / 3600
                let m = (secondsAgo % 3600) / 60
                pingAgeInfo = "Немає пінгу \(h)г \(m)хв (з \(timeStr))"
            }
        } else if let name = checkName, !name.isEmpty {
            pingAgeInfo = "Датчик «\(name)»"
        } else {
            pingAgeInfo = "Датчик Healthchecks.io"
        }
        
        switch rawStatus {
        case "up":
            return LiveSensorStatus(
                source: .healthchecks,
                state: .online,
                statusText: "ESP32 / Healthchecks: Світло Є",
                detailText: pingAgeInfo,
                eventTimestamp: lastPingDate,
                checkedAt: now,
                detectedGroup: detectedGroup
            )
        case "down":
            return LiveSensorStatus(
                source: .healthchecks,
                state: .offline,
                statusText: "ESP32 / Healthchecks: Світла НЕМАЄ",
                detailText: pingAgeInfo,
                eventTimestamp: lastPingDate,
                checkedAt: now,
                detectedGroup: detectedGroup
            )
        case "grace", "late":
            return LiveSensorStatus(
                source: .healthchecks,
                state: .grace,
                statusText: "ESP32 / Healthchecks: Затримка пінгу",
                detailText: pingAgeInfo,
                eventTimestamp: lastPingDate,
                checkedAt: now,
                detectedGroup: detectedGroup
            )
        case "new", "paused":
            return LiveSensorStatus(
                source: .healthchecks,
                state: .unknown,
                statusText: "Healthchecks: Очікується перший пінг",
                detailText: pingAgeInfo,
                eventTimestamp: lastPingDate,
                checkedAt: now,
                detectedGroup: detectedGroup
            )
        default:
            return LiveSensorStatus(
                source: .healthchecks,
                state: .error,
                statusText: "Healthchecks: Невідомий статус (\(rawStatus))",
                detailText: pingAgeInfo,
                eventTimestamp: lastPingDate,
                checkedAt: now,
                detectedGroup: detectedGroup
            )
        }
    }
    
    // MARK: - Helpers
    private static func extractTelegramMessageDate(from block: String) -> Date? {
        // Look for <time datetime="2026-10-28T14:22:10+00:00"
        guard let timeRange = block.range(of: "datetime=\"") else { return nil }
        let afterAttr = String(block[timeRange.upperBound...])
        guard let quoteEnd = afterAttr.firstIndex(of: "\"") else { return nil }
        let isoStr = String(afterAttr[..<quoteEnd])
        return parseISODate(isoStr)
    }
    
    /// If the first line of a SvitloBot message contains an explicit HH:mm (e.g. "🔴 08:00 Світло зникло"),
    /// refine the message's date in Europe/Kyiv timezone to that exact hour and minute.
    private static func refineDateWithExplicitTimeInText(baseDate: Date?, text: String) -> Date? {
        guard let baseDate = baseDate else { return nil }
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let pattern = "(?:^|\\s|о\\s)(\\d{1,2}):(\\d{2})(?:\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)),
              match.numberOfRanges >= 3,
              let hRange = Range(match.range(at: 1), in: firstLine),
              let mRange = Range(match.range(at: 2), in: firstLine),
              let hour = Int(firstLine[hRange]),
              let minute = Int(firstLine[mRange]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return baseDate
        }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ScheduleCalculator.kyivTimeZone
        var comps = cal.dateComponents([.year, .month, .day], from: baseDate)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let refined = cal.date(from: comps), abs(refined.timeIntervalSince(baseDate)) < 6 * 3600 {
            return refined
        }
        return baseDate
    }
    
    private static func parseISODate(_ str: String?) -> Date? {
        guard let str = str, !str.isEmpty else { return nil }
        if let d = isoFormatterWithFractional.date(from: str) {
            return d
        }
        if let d = isoFormatterStandard.date(from: str) {
            return d
        }
        return nil
    }
    
    private static func formatEventDetail(prefix: String, eventDate: Date?, channelName: String, now: Date) -> String {
        guard let eventDate = eventDate else {
            return "Канал @\(channelName)"
        }
        let timeStr = kyivTimeFormatter.string(from: eventDate)
        let minutesAgo = max(0, Int(now.timeIntervalSince(eventDate) / 60))
        if minutesAgo < 1 {
            return "\(prefix) щойно о \(timeStr) (@\(channelName))"
        } else if minutesAgo < 60 {
            return "\(prefix) о \(timeStr) (\(minutesAgo) хв тому • @\(channelName))"
        } else {
            let h = minutesAgo / 60
            let m = minutesAgo % 60
            let dur = m > 0 ? "\(h)г \(m)хв" : "\(h) год"
            return "\(prefix) о \(timeStr) (\(dur) тому • @\(channelName))"
        }
    }
    
    private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [String: String] = [
            "&quot;": "\"",
            "&#39;": "'",
            "&#039;": "'",
            "&apos;": "'",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text
    }
    
    // MARK: - Auto-Detection of Yasno / DTEK Outage Group
    public static func detectGroup(
        from texts: [String],
        channelSlug: String = "",
        jsonDict: [String: Any]? = nil
    ) -> String? {
        // 1. Direct JSON check if API provided it
        if let json = jsonDict {
            if let g = json["group"] as? String ?? (json["queue"] as? String) ?? (json["dtek_group"] as? String),
               let normalized = normalizeDetectedGroup(g) {
                return normalized
            }
            if let gNum = json["group"] as? Int {
                if let sub = json["subgroup"] as? Int {
                    return "\(gNum).\(sub)"
                }
                return normalizeDetectedGroup("\(gNum)")
            }
        }
        
        // 2. High-priority texts: channel description, title, pinned messages, recent messages
        for text in texts where !text.isEmpty {
            if let group = findGroupInText(text) {
                return group
            }
        }
        
        // 3. Fallback: Channel slug (e.g. svitlo_kyiv_3_1, group_4_2, cherha_2)
        if !channelSlug.isEmpty {
            if let group = findGroupInSlug(channelSlug) {
                return group
            }
        }
        
        return nil
    }
    
    public static func findGroupInText(_ text: String) -> String? {
        let lower = text.lowercased()
        
        // 1. Group with subgroup X.Y (e.g. 3.1, 4.2, 34.1, 46.1)
        let patternsWithSubgroup = [
            #"(?:черг[аиіу]|груп[аиіу]|group|queue|grp)\s*[:№#\-–—]?\s*([1-9][0-9]?[.,][1-4])\b"#,
            #"([1-9][0-9]?[.,][1-4])\s*(?:-?(?:[а-яіїє]{1,4}\s*)?)(?:черг[аиіу]|груп[аиіу]|group|queue)"#,
            #"(?:дтек|dtek|yasno|ясно)\s*[:№#\-–—]?\s*(?:черг[аиіу]|груп[аиіу])?\s*([1-9][0-9]?[.,][1-4])\b"#
        ]
        
        for pattern in patternsWithSubgroup {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: lower, options: [], range: NSRange(lower.startIndex..., in: lower)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: lower) {
                let found = String(lower[range]).replacingOccurrences(of: ",", with: ".")
                return normalizeDetectedGroup(found)
            }
        }
        
        // 2. Single-number group X (1..60)
        let patternsSingleDigit = [
            #"(?:черг[аиіу]|груп[аиіу]|group|queue|grp)\s*[:№#\-–—]?\s*([1-9][0-9]?)\b(?![.,][0-9])"#,
            #"([1-9][0-9]?)\s*(?:-?(?:[а-яіїє]{1,4}\s*)?)(?:черг[аиіу]|груп[аиіу]|group|queue)"#,
            #"(?:дтек|dtek|yasno|ясно)\s*[:№#\-–—]?\s*(?:черг[аиіу]|груп[аиіу])\s*([1-9][0-9]?)\b(?![.,][0-9])"#
        ]
        
        for pattern in patternsSingleDigit {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: lower, options: [], range: NSRange(lower.startIndex..., in: lower)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: lower) {
                return normalizeDetectedGroup(String(lower[range]))
            }
        }
        
        return nil
    }
    
    public static func findGroupInSlug(_ slug: String) -> String? {
        let lower = slug.lowercased()
        
        // [_-]X[_-]Y (e.g. svitlo_3_1 or group-4-2 or svitlobot_1_1 or svitlo_46_1)
        let slugWithSubgroup = [
            #"(?:group|cherha|svitlo|dtek|grp)[_-]?([1-9][0-9]?)[_-]([1-4])\b"#,
            #"[_-]([1-9][0-9]?)[_-]([1-4])\b"#,
            #"\b([1-9][0-9]?)_([1-4])\b"#
        ]
        for pattern in slugWithSubgroup {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: lower, options: [], range: NSRange(lower.startIndex..., in: lower)),
               match.numberOfRanges > 2,
               let r1 = Range(match.range(at: 1), in: lower),
               let r2 = Range(match.range(at: 2), in: lower) {
                return "\(lower[r1]).\(lower[r2])"
            }
        }
        
        // Single number in slug: group_3 or cherha_4
        let slugSingle = [
            #"(?:group|cherha|grp)[_-]?([1-9][0-9]?)\b"#,
            #"[_-]([1-9][0-9]?)\b"#
        ]
        for pattern in slugSingle {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: lower, options: [], range: NSRange(lower.startIndex..., in: lower)),
               match.numberOfRanges > 1,
               let r1 = Range(match.range(at: 1), in: lower) {
                return String(lower[r1])
            }
        }
        
        return nil
    }
    
    public static func normalizeDetectedGroup(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ".")
        guard let first = parts.first, let main = Int(first), main >= 1 && main <= 60 else {
            return nil
        }
        if parts.count >= 2, let sub = Int(parts[1]), sub >= 1 && sub <= 4 {
            return "\(main).\(sub)"
        }
        return "\(main)"
    }
    
    public static func extractCleanChannelTitle(from html: String) -> String? {
        var rawTitle: String? = nil
        let markers = [
            "tgme_channel_info_header_title",
            "tgme_channel_info_title",
            "tgme_page_title"
        ]
        for marker in markers {
            if let range = html.range(of: marker) {
                let after = html[range.upperBound...]
                if let closeTag = after.range(of: ">"),
                   let endDiv = after.range(of: "</div>") {
                    let titleHtml = String(after[closeTag.upperBound..<endDiv.lowerBound])
                    let stripped = stripHTML(titleHtml).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stripped.isEmpty {
                        rawTitle = stripped
                        break
                    }
                }
            }
        }
        if rawTitle == nil, let ogTitleRange = html.range(of: "property=\"og:title\" content=\"") {
            let rest = html[ogTitleRange.upperBound...]
            if let quoteEnd = rest.firstIndex(of: "\"") {
                let stripped = stripHTML(String(rest[..<quoteEnd])).trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty {
                    rawTitle = stripped
                }
            }
        }
        
        guard var title = rawTitle else { return nil }
        
        let botWords = ["світлобот", "світло бот", "svitlobot", "світло", "bot", "бот"]
        for bw in botWords {
            if let r = title.range(of: bw, options: .caseInsensitive) {
                title.removeSubrange(r)
            }
        }
        
        let symbolsToRemove: [Character] = ["⚡", "⚡️", "💡", "🟢", "🔴", "⚫", "⚫️", "🏢", "🏠", "📍", "🇺🇦", "|", "-", "–", "—", ":", "•", "«", "»", "\"", "“", "”"]
        title = title.filter { !symbolsToRemove.contains($0) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return title.isEmpty ? nil : title
    }
    
    public static func extractPlannedHintsFromMessage(rawText: String, messageDate: Date?, now: Date) -> [OutageSlot] {
        if let msgDate = messageDate {
            if now.timeIntervalSince(msgDate) > 86400 {
                return []
            }
        }
        
        var slots: [OutageSlot] = []
        let patternInterval = #"([0-2]?[0-9]):([0-5][0-9])\s*(?:[-–—→]|до)\s*([0-2]?[0-9]):([0-5][0-9])"#
        if let regex = try? NSRegularExpression(pattern: patternInterval) {
            let matches = regex.matches(in: rawText, range: NSRange(rawText.startIndex..., in: rawText))
            for match in matches where match.numberOfRanges >= 5 {
                guard let h1R = Range(match.range(at: 1), in: rawText),
                      let m1R = Range(match.range(at: 2), in: rawText),
                      let h2R = Range(match.range(at: 3), in: rawText),
                      let m2R = Range(match.range(at: 4), in: rawText),
                      let h1 = Int(rawText[h1R]),
                      let m1 = Int(rawText[m1R]),
                      let h2 = Int(rawText[h2R]),
                      let m2 = Int(rawText[m2R]) else { continue }
                
                let startM = h1 * 60 + m1
                var endM = h2 * 60 + m2
                if endM == 0 && (h2 == 0 || h2 == 24) { endM = 1440 }
                if endM > startM {
                    slots.append(OutageSlot(startMinutes: startM, endMinutes: endM, type: .off))
                }
            }
        }
        
        return slots
    }
    
    public static func extractChannelMetadataTexts(from html: String) -> [String] {
        var texts: [String] = []
        
        // 1. og:description and og:title
        if let ogDescRange = html.range(of: "property=\"og:description\" content=\"") {
            let rest = html[ogDescRange.upperBound...]
            if let quoteEnd = rest.firstIndex(of: "\"") {
                let desc = String(rest[..<quoteEnd])
                texts.append(stripHTML(desc))
            }
        }
        if let ogTitleRange = html.range(of: "property=\"og:title\" content=\"") {
            let rest = html[ogTitleRange.upperBound...]
            if let quoteEnd = rest.firstIndex(of: "\"") {
                let title = String(rest[..<quoteEnd])
                texts.append(stripHTML(title))
            }
        }
        
        // 2. tgme_channel_info_description / tgme_page_description
        for marker in ["tgme_channel_info_description", "tgme_page_description"] {
            if let range = html.range(of: marker) {
                let after = html[range.upperBound...]
                if let closeTag = after.range(of: ">"),
                   let endDiv = after.range(of: "</div>") {
                    let descHtml = String(after[closeTag.upperBound..<endDiv.lowerBound])
                    texts.append(stripHTML(descHtml))
                }
            }
        }
        
        // 3. tgme_channel_info_title / tgme_page_title
        for marker in ["tgme_channel_info_title", "tgme_page_title"] {
            if let range = html.range(of: marker) {
                let after = html[range.upperBound...]
                if let closeTag = after.range(of: ">"),
                   let endDiv = after.range(of: "</div>") {
                    let titleHtml = String(after[closeTag.upperBound..<endDiv.lowerBound])
                    texts.append(stripHTML(titleHtml))
                }
            }
        }
        
        // 4. Pinned message text
        if let pinnedRange = html.range(of: "tgme_widget_message_pinned") {
            let after = html[pinnedRange.upperBound...]
            if let textRange = after.range(of: "tgme_widget_message_text") {
                let afterText = after[textRange.upperBound...]
                if let closeTag = afterText.range(of: ">"),
                   let endDiv = afterText.range(of: "</div>") {
                    let pinnedHtml = String(afterText[closeTag.upperBound..<endDiv.lowerBound])
                    texts.append(stripHTML(pinnedHtml))
                }
            }
        }
        
        return texts
    }
}
