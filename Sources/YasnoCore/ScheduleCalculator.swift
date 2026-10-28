import Foundation

public struct ScheduleCalculator {
    public static let kyivTimeZone = TimeZone(identifier: "Europe/Kyiv") ?? TimeZone(secondsFromGMT: 7200)!
    
    public static let kyivCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kyivTimeZone
        return cal
    }()
    
    /// Gets current minute of day (0 .. 1439) in Europe/Kyiv timezone
    public static func kyivMinuteOfDay(for date: Date = Date()) -> Int {
        let components = kyivCalendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }
    
    /// Gets the start of the day in Europe/Kyiv timezone
    public static func kyivStartOfDay(for date: Date = Date()) -> Date {
        return kyivCalendar.startOfDay(for: date)
    }
    
    /// Gets the start of the NEXT day in Europe/Kyiv timezone (DST-safe, unlike `+86400`)
    public static func kyivStartOfNextDay(for date: Date = Date()) -> Date {
        let start = kyivCalendar.startOfDay(for: date)
        return kyivCalendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
    }
    
    /// Converts minute-of-day (0...1440) of a given Kyiv day into an absolute Date (DST-safe)
    public static func kyivDate(dayStart: Date, minutes: Int) -> Date {
        let h = minutes / 60
        let m = minutes % 60
        if h >= 24 {
            let next = kyivCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
            return kyivCalendar.date(byAdding: .minute, value: (h - 24) * 60 + m, to: next) ?? next
        }
        return kyivCalendar.date(bySettingHour: h, minute: m, second: 0, of: dayStart) ?? dayStart.addingTimeInterval(TimeInterval(minutes * 60))
    }
    
    /// Determines current status based on today's slots
    public static func calculateCurrentStatus(slots: [OutageSlot], currentMinute: Int) -> OutageType {
        for slot in slots {
            if slot.contains(minuteOfDay: currentMinute) {
                return slot.type
            }
        }
        return .on
    }
    
    /// Calculates the next turn off or turn on event
    public static func calculateNextEvent(
        todaySlots: [OutageSlot],
        tomorrowSlots: [OutageSlot],
        currentDate: Date = Date(),
        sensor: LiveSensorStatus? = nil
    ) -> NextEvent {
        let currentMinute = kyivMinuteOfDay(for: currentDate)
        let todayStart = kyivStartOfDay(for: currentDate)
        let tomorrowStart = kyivStartOfNextDay(for: currentDate)
        
        let activeSlot = todaySlots.first(where: { $0.contains(minuteOfDay: currentMinute) })
        let currentStatus = activeSlot?.type ?? .on
        let isLiveFactSlot = (activeSlot?.isActualFact == true)
        
        let isCurrentlyOff: Bool
        if let sensor = sensor, (sensor.state == .online || sensor.state == .offline) {
            isCurrentlyOff = (sensor.state == .offline)
        } else {
            isCurrentlyOff = (currentStatus == .off) || (currentStatus == .possible && !isLiveFactSlot)
        }
        
        if isCurrentlyOff {
            // Power is currently OFF -> determine if we are in a scheduled outage or an unplanned outage during a green slot
            if let activeSlot = activeSlot {
                // If activeSlot is an orange (.possible, isActualFact: true) window while sensor is OFFLINE,
                // that means the planned schedule says power SHOULD be ON until activeSlot.endMinutes!
                if activeSlot.type == .possible && activeSlot.isActualFact {
                    // Check if a scheduled outage starts right at activeSlot.endMinutes and we are within 30 min of it (early turn-off)
                    if let upcomingOff = todaySlots.first(where: { $0.startMinutes == activeSlot.endMinutes && ($0.type == .off || ($0.type == .possible && !$0.isActualFact)) }),
                       (activeSlot.endMinutes - currentMinute) <= 30 {
                        var targetEndMinutes = upcomingOff.endMinutes
                        var targetDate = kyivDate(dayStart: todayStart, minutes: upcomingOff.endMinutes)
                        if upcomingOff.endMinutes >= 1440,
                           let firstTomorrow = tomorrowSlots.first,
                           firstTomorrow.startMinutes == 0,
                           (firstTomorrow.type == .off || firstTomorrow.type == .possible) {
                            targetEndMinutes = firstTomorrow.endMinutes
                            targetDate = kyivDate(dayStart: tomorrowStart, minutes: firstTomorrow.endMinutes)
                        }
                        let remaining = max(0, Int(ceil(targetDate.timeIntervalSince(currentDate) / 60.0)))
                        return NextEvent(
                            eventType: .turnsOn(atMinutes: targetEndMinutes, atDate: targetDate),
                            targetDate: targetDate,
                            minutesRemaining: remaining
                        )
                    }
                    
                    // Unplanned outage during a green (.on) slot!
                    let targetDate = kyivDate(dayStart: todayStart, minutes: activeSlot.endMinutes)
                    let remaining = max(0, Int(ceil(targetDate.timeIntervalSince(currentDate) / 60.0)))
                    return NextEvent(
                        eventType: .unplannedOutage(untilMinutes: activeSlot.endMinutes, atDate: targetDate),
                        targetDate: targetDate,
                        minutesRemaining: remaining
                    )
                }
                
                var targetEndMinutes = activeSlot.endMinutes
                var targetDate = kyivDate(dayStart: todayStart, minutes: activeSlot.endMinutes)
                
                // If outage reaches midnight (1440), check if tomorrow starts with an outage
                if activeSlot.endMinutes >= 1440,
                   let firstTomorrow = tomorrowSlots.first,
                   firstTomorrow.startMinutes == 0,
                   (firstTomorrow.type == .off || firstTomorrow.type == .possible) {
                    targetEndMinutes = firstTomorrow.endMinutes
                    targetDate = kyivDate(dayStart: tomorrowStart, minutes: firstTomorrow.endMinutes)
                }
                
                let remaining = max(0, Int(ceil(targetDate.timeIntervalSince(currentDate) / 60.0)))
                return NextEvent(
                    eventType: .turnsOn(atMinutes: targetEndMinutes, atDate: targetDate),
                    targetDate: targetDate,
                    minutesRemaining: remaining
                )
            }
        } else {
            // Power is currently ON -> find next turn OFF (Definite or planned Possible)
            // 1. Look in today's remaining slots
            if let nextOffToday = todaySlots.first(where: { $0.startMinutes > currentMinute && ($0.type == .off || ($0.type == .possible && !$0.isActualFact)) }) {
                let targetDate = kyivDate(dayStart: todayStart, minutes: nextOffToday.startMinutes)
                let remaining = max(0, Int(ceil(targetDate.timeIntervalSince(currentDate) / 60.0)))
                return NextEvent(
                    eventType: .turnsOff(atMinutes: nextOffToday.startMinutes, atDate: targetDate),
                    targetDate: targetDate,
                    minutesRemaining: remaining
                )
            }
            
            // 2. Look in tomorrow's slots
            if let nextOffTomorrow = tomorrowSlots.first(where: { $0.type == .off || $0.type == .possible }) {
                let targetDate = kyivDate(dayStart: tomorrowStart, minutes: nextOffTomorrow.startMinutes)
                let remaining = max(0, Int(ceil(targetDate.timeIntervalSince(currentDate) / 60.0)))
                return NextEvent(
                    eventType: .turnsOff(atMinutes: nextOffTomorrow.startMinutes, atDate: targetDate),
                    targetDate: targetDate,
                    minutesRemaining: remaining
                )
            }
        }
        
        return NextEvent(eventType: .none, targetDate: nil, minutesRemaining: 0)
    }
    
    /// Merges consecutive slots that share the same OutageType
    public static func mergeConsecutiveSlots(_ rawSlots: [OutageSlot]) -> [OutageSlot] {
        guard !rawSlots.isEmpty else { return [] }
        let sorted = rawSlots.sorted { $0.startMinutes < $1.startMinutes }
        var result: [OutageSlot] = []
        
        var currentStart = sorted[0].startMinutes
        var currentEnd = sorted[0].endMinutes
        var currentType = sorted[0].type
        var currentIsFact = sorted[0].isActualFact
        
        for i in 1..<sorted.count {
            let nextSlot = sorted[i]
            if nextSlot.type == currentType && nextSlot.startMinutes <= currentEnd {
                currentEnd = max(currentEnd, nextSlot.endMinutes)
                currentIsFact = currentIsFact || nextSlot.isActualFact
            } else {
                if currentEnd > currentStart {
                    result.append(OutageSlot(startMinutes: currentStart, endMinutes: currentEnd, type: currentType, isActualFact: currentIsFact))
                }
                currentStart = nextSlot.startMinutes
                currentEnd = nextSlot.endMinutes
                currentType = nextSlot.type
                currentIsFact = nextSlot.isActualFact
            }
        }
        if currentEnd > currentStart {
            result.append(OutageSlot(startMinutes: currentStart, endMinutes: currentEnd, type: currentType, isActualFact: currentIsFact))
        }
        return result
    }
    
    /// Reconciles today's planned Yasno schedule with actual past history from SvitloBot / Healthchecks.io.
    /// Everything up to `currentMinute` (0 ..< cutoffMinute) is replaced by actual sensor fact,
    /// while active slots that disagree with the schedule are highlighted in orange (`.possible`),
    /// and future slots follow the planned schedule.
    public static func reconcileTodaySlotsWithLiveSensor(
        plannedSlots: [OutageSlot],
        sensor: LiveSensorStatus?,
        currentDate: Date = Date()
    ) -> [OutageSlot] {
        guard let sensor = sensor,
              (sensor.state == .online || sensor.state == .offline) else {
            return plannedSlots
        }
        
        let currentMinute = max(0, min(1440, kyivMinuteOfDay(for: currentDate)))
        guard currentMinute > 0 else { return plannedSlots }
        
        let todayStart = kyivStartOfDay(for: currentDate)
        let currentActualType: OutageType = (sensor.state == .online) ? .on : .off
        
        // 1. Gather & sort verified state transitions (never treat heartbeat last_ping as a flip!)
        let allTransitions = sensor.transitions.sorted { $0.timestamp < $1.timestamp }
        
        // If no transition history is available yet (e.g. newly added Badge URL), only reconcile the active slot at currentMinute
        if allTransitions.isEmpty {
            let normalized = plannedSlots.isEmpty ? fillGapsWithPowerOn(slots: []) : plannedSlots
            var adjusted: [OutageSlot] = []
            for slot in normalized {
                if slot.contains(minuteOfDay: currentMinute) {
                    if (slot.type == .off || slot.type == .possible) && sensor.state == .online {
                        adjusted.append(OutageSlot(startMinutes: slot.startMinutes, endMinutes: slot.endMinutes, type: .possible, isActualFact: true))
                    } else if slot.type == .on && sensor.state == .offline {
                        if currentMinute > slot.startMinutes {
                            adjusted.append(OutageSlot(startMinutes: slot.startMinutes, endMinutes: currentMinute, type: .on, isActualFact: false))
                        }
                        adjusted.append(OutageSlot(startMinutes: currentMinute, endMinutes: slot.endMinutes, type: .possible, isActualFact: true))
                    } else {
                        adjusted.append(slot)
                    }
                } else {
                    adjusted.append(slot)
                }
            }
            return mergeConsecutiveSlots(adjusted)
        }
        
        let beforeToday = allTransitions.filter { $0.timestamp < todayStart }
        let todayTransitions = allTransitions.filter {
            $0.timestamp >= todayStart && $0.timestamp <= currentDate.addingTimeInterval(120)
        }
        let normalizedPlanned = plannedSlots.isEmpty ? fillGapsWithPowerOn(slots: []) : plannedSlots
        
        // 2. Build actual slots for 0 ..< currentMinute
        var rawPastSlots: [OutageSlot] = []
        var cursor = 0
        var runningType: OutageType
        
        if let lastBefore = beforeToday.last {
            runningType = lastBefore.isPowerOn ? .on : .off
        } else if let firstToday = todayTransitions.first {
            if firstToday.isPowerOn {
                // First recorded event today is "Power ON" (e.g. at 09:00) and we have no prior history before today.
                // Instead of assuming power was off since 00:00 midnight, check if a planned outage started earlier this morning.
                let firstMin = max(0, min(currentMinute, kyivMinuteOfDay(for: firstToday.timestamp)))
                if let matchingPlannedOff = normalizedPlanned.last(where: { ($0.type == .off || $0.type == .possible) && $0.startMinutes <= firstMin && $0.endMinutes > 0 }),
                   matchingPlannedOff.startMinutes > 0 {
                    for pSlot in normalizedPlanned where pSlot.startMinutes < matchingPlannedOff.startMinutes {
                        let endM = min(pSlot.endMinutes, matchingPlannedOff.startMinutes)
                        if endM > cursor {
                            rawPastSlots.append(OutageSlot(startMinutes: cursor, endMinutes: endM, type: pSlot.type, isActualFact: false))
                            cursor = endM
                        }
                    }
                }
                runningType = .off
            } else {
                runningType = .on
            }
        } else {
            runningType = currentActualType
        }
        
        for transition in todayTransitions {
            let m = max(0, min(currentMinute, kyivMinuteOfDay(for: transition.timestamp)))
            let nextType: OutageType = transition.isPowerOn ? .on : .off
            if m > cursor {
                rawPastSlots.append(OutageSlot(startMinutes: cursor, endMinutes: m, type: runningType, isActualFact: true))
                cursor = m
            }
            runningType = nextType
        }
        
        if currentMinute > cursor {
            rawPastSlots.append(OutageSlot(startMinutes: cursor, endMinutes: currentMinute, type: currentActualType, isActualFact: true))
        }
        
        // Filter out <2 min router-reboot blips that already recovered
        let mergedPast = mergeConsecutiveSlots(rawPastSlots).map { slot -> OutageSlot in
            if slot.type == .off && slot.durationMinutes < 2 && slot.endMinutes < currentMinute {
                return OutageSlot(startMinutes: slot.startMinutes, endMinutes: slot.endMinutes, type: .on, isActualFact: true)
            }
            return slot
        }
        let cleanPastSlots = mergeConsecutiveSlots(mergedPast)
        
        // 4. Build future slots for currentMinute ..< 1440 from planned schedule.
        // - Case A: Planned slot is OFF (e.g. 08:00-12:00) AND sensor confirms power is ON (e.g. turned on at 09:00):
        //   The current ON window inside that planned outage (09:00-12:00) is marked `.possible` (orange: power is ON, but may be turned off again until 12:00).
        // - Case B: Planned slot is ON (e.g. 10:00-13:00) AND sensor confirms power is OFF (e.g. off since 10:00 or 10:30):
        //   The past part (10:00 ..< currentMinute) is already `.off` (red, fact) in adjustedPastSlots,
        //   and the remaining part of this planned ON slot (currentMinute ..< 13:00) is marked `.possible` (orange: power is currently OFF outside schedule, waiting for restoration).
        //   Once 13:00 passes (or when power comes back on), the entire passed outage interval is red (.off) and any restored interval is green (.on).
        var adjustedPastSlots = cleanPastSlots
        var futureSlots: [OutageSlot] = []
        
        for slot in normalizedPlanned {
            if slot.endMinutes <= currentMinute {
                // Completely in the past -> replaced by adjustedPastSlots
                continue
            } else if slot.startMinutes <= currentMinute && slot.endMinutes > currentMinute {
                // Currently active planned slot spanning currentMinute
                if (slot.type == .off || slot.type == .possible) && sensor.state == .online {
                    let streakStart: Int
                    if let lastPast = adjustedPastSlots.last, lastPast.type == .on {
                        streakStart = lastPast.startMinutes
                    } else {
                        streakStart = currentMinute
                    }
                    let orangeStart = max(slot.startMinutes, streakStart)
                    
                    // Trim adjustedPastSlots back to orangeStart so [orangeStart ..< slot.endMinutes] becomes a single orange .possible block
                    if let lastPast = adjustedPastSlots.last, lastPast.type == .on, lastPast.endMinutes > orangeStart {
                        adjustedPastSlots.removeLast()
                        if orangeStart > lastPast.startMinutes {
                            adjustedPastSlots.append(OutageSlot(
                                startMinutes: lastPast.startMinutes,
                                endMinutes: orangeStart,
                                type: .on,
                                isActualFact: lastPast.isActualFact
                            ))
                        }
                    }
                    
                    futureSlots.append(OutageSlot(
                        startMinutes: orangeStart,
                        endMinutes: slot.endMinutes,
                        type: .possible,
                        isActualFact: true
                    ))
                } else if slot.type == .on && sensor.state == .offline {
                    // Schedule says power should be ON right now, but sensor confirms power is OFF!
                    // Past portion up to currentMinute is already .off (red, isActualFact: true) in adjustedPastSlots.
                    // Mark the remaining portion of this planned .on slot (currentMinute ..< slot.endMinutes) as .possible (orange).
                    futureSlots.append(OutageSlot(
                        startMinutes: currentMinute,
                        endMinutes: slot.endMinutes,
                        type: .possible,
                        isActualFact: true
                    ))
                } else {
                    futureSlots.append(OutageSlot(startMinutes: currentMinute, endMinutes: slot.endMinutes, type: slot.type, isActualFact: false))
                }
            } else {
                futureSlots.append(OutageSlot(startMinutes: slot.startMinutes, endMinutes: slot.endMinutes, type: slot.type, isActualFact: false))
            }
        }
        
        return mergeConsecutiveSlots(adjustedPastSlots + futureSlots)
    }
    
    /// For WidgetKit timeline entries scheduled in the FUTURE (e.g. at 18:00 while now is 12:00):
    /// the past (00:00 ..< now) is taken from real sensor facts, but everything after `now` follows the planned schedule,
    /// because we cannot know the sensor state in the future.
    public static func reconcileForFutureEntry(
        plannedSlots: [OutageSlot],
        sensor: LiveSensorStatus?,
        now: Date,
        entryDate: Date
    ) -> [OutageSlot] {
        guard let sensor = sensor,
              (sensor.state == .online || sensor.state == .offline),
              kyivStartOfDay(for: now) == kyivStartOfDay(for: entryDate) else {
            return plannedSlots
        }
        let nowMinute = kyivMinuteOfDay(for: now)
        guard nowMinute > 0 else { return plannedSlots }
        let actualNow: OutageType = (sensor.state == .online) ? .on : .off
        let atNow = reconcileTodaySlotsWithLiveSensor(plannedSlots: plannedSlots, sensor: sensor, currentDate: now)
        
        var result: [OutageSlot] = []
        for slot in atNow where slot.startMinutes < nowMinute {
            let isLiveWindow = (slot.type == .possible && slot.isActualFact)
            result.append(OutageSlot(
                startMinutes: slot.startMinutes,
                endMinutes: min(slot.endMinutes, nowMinute),
                type: isLiveWindow ? actualNow : slot.type,
                isActualFact: slot.isActualFact
            ))
        }
        let normalizedPlanned = plannedSlots.isEmpty ? fillGapsWithPowerOn(slots: []) : plannedSlots
        for slot in normalizedPlanned where slot.endMinutes > nowMinute {
            result.append(OutageSlot(
                startMinutes: max(slot.startMinutes, nowMinute),
                endMinutes: slot.endMinutes,
                type: slot.type,
                isActualFact: false
            ))
        }
        return mergeConsecutiveSlots(result)
    }
    
    /// Normalizes raw slots into a complete 24h day representation (0 .. 1440 min)
    public static func fillGapsWithPowerOn(slots: [OutageSlot]) -> [OutageSlot] {
        var complete: [OutageSlot] = []
        let sorted = slots.sorted { $0.startMinutes < $1.startMinutes }
        var cursor = 0
        
        for slot in sorted {
            if slot.startMinutes > cursor {
                complete.append(OutageSlot(startMinutes: cursor, endMinutes: slot.startMinutes, type: .on))
            }
            complete.append(slot)
            cursor = max(cursor, slot.endMinutes)
        }
        
        if cursor < 1440 {
            complete.append(OutageSlot(startMinutes: cursor, endMinutes: 1440, type: .on))
        }
        
        return mergeConsecutiveSlots(complete)
    }
    
    /// Creates realistic sample outage data for preview/fallback
    public static func makeSampleSlots() -> (today: [OutageSlot], tomorrow: [OutageSlot]) {
        let todayRaw = [
            OutageSlot(startMinutes: 0, endMinutes: 360, type: .on),          // 00:00 - 06:00 ON
            OutageSlot(startMinutes: 360, endMinutes: 600, type: .off),        // 06:00 - 10:00 OFF
            OutageSlot(startMinutes: 600, endMinutes: 840, type: .on),         // 10:00 - 14:00 ON
            OutageSlot(startMinutes: 840, endMinutes: 1080, type: .possible),   // 14:00 - 18:00 POSSIBLE
            OutageSlot(startMinutes: 1080, endMinutes: 1320, type: .off),      // 18:00 - 22:00 OFF
            OutageSlot(startMinutes: 1320, endMinutes: 1440, type: .on)        // 22:00 - 24:00 ON
        ]
        
        let tomorrowRaw = [
            OutageSlot(startMinutes: 0, endMinutes: 480, type: .on),          // 00:00 - 08:00 ON
            OutageSlot(startMinutes: 480, endMinutes: 720, type: .off),        // 08:00 - 12:00 OFF
            OutageSlot(startMinutes: 720, endMinutes: 960, type: .on),         // 12:00 - 16:00 ON
            OutageSlot(startMinutes: 960, endMinutes: 1200, type: .off),       // 16:00 - 20:00 OFF
            OutageSlot(startMinutes: 1200, endMinutes: 1440, type: .on)        // 20:00 - 24:00 ON
        ]
        
        return (today: fillGapsWithPowerOn(slots: todayRaw), tomorrow: fillGapsWithPowerOn(slots: tomorrowRaw))
    }
}
