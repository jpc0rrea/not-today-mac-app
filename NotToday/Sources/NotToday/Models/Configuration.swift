import Foundation

// MARK: - Main Configuration
struct Configuration: Codable {
    var blockedSites: [String]
    var schedule: Schedule
    var enabled: Bool

    static let defaultConfig = Configuration(
        blockedSites: [
            "twitter.com",
            "www.twitter.com",
            "x.com",
            "www.x.com",
            "facebook.com",
            "www.facebook.com",
            "instagram.com",
            "www.instagram.com",
            "reddit.com",
            "www.reddit.com",
            "youtube.com",
            "www.youtube.com",
            "tiktok.com",
            "www.tiktok.com",
            "netflix.com",
            "www.netflix.com"
        ],
        schedule: Schedule.default,
        enabled: true
    )
}

// MARK: - Day Schedule (per-day time configuration)
struct DaySchedule: Codable, Equatable {
    var enabled: Bool
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var startTimeString: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endTimeString: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    static let defaultWeekday = DaySchedule(
        enabled: true,
        startHour: 9,
        startMinute: 0,
        endHour: 19,
        endMinute: 0
    )

    static let defaultWeekend = DaySchedule(
        enabled: false,
        startHour: 10,
        startMinute: 0,
        endHour: 14,
        endMinute: 0
    )

    static let disabled = DaySchedule(
        enabled: false,
        startHour: 9,
        startMinute: 0,
        endHour: 17,
        endMinute: 0
    )
}

// MARK: - Schedule Configuration
struct Schedule: Codable {
    var daySchedules: [DayOfWeek: DaySchedule]

    static let `default`: Schedule = {
        var schedules: [DayOfWeek: DaySchedule] = [:]
        for day in DayOfWeek.allCases {
            switch day {
            case .saturday, .sunday:
                schedules[day] = .defaultWeekend
            default:
                schedules[day] = .defaultWeekday
            }
        }
        return Schedule(daySchedules: schedules)
    }()

    func scheduleFor(day: DayOfWeek) -> DaySchedule {
        daySchedules[day] ?? .disabled
    }

    func isActiveNow() -> Bool {
        let calendar = Calendar.current
        let now = Date()

        // Get current day of week
        let weekday = calendar.component(.weekday, from: now)
        guard let currentDay = DayOfWeek.from(calendarWeekday: weekday) else {
            return false
        }

        // Get schedule for today
        let todaySchedule = scheduleFor(day: currentDay)

        // Check if today is enabled
        guard todaySchedule.enabled else {
            return false
        }

        // Check if current time is within the scheduled window
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute
        let startMinutes = todaySchedule.startHour * 60 + todaySchedule.startMinute
        let endMinutes = todaySchedule.endHour * 60 + todaySchedule.endMinute

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    func currentDayEndTime() -> String? {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)

        guard let currentDay = DayOfWeek.from(calendarWeekday: weekday) else {
            return nil
        }

        let todaySchedule = scheduleFor(day: currentDay)
        guard todaySchedule.enabled else { return nil }

        return todaySchedule.endTimeString
    }

    func nextActivation() -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // Try to find the next activation time within the next 7 days
        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: checkDate)
            guard let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) else {
                continue
            }

            let daySchedule = scheduleFor(day: dayOfWeek)
            guard daySchedule.enabled else {
                continue
            }

            // Create the start time for this day
            var components = calendar.dateComponents([.year, .month, .day], from: checkDate)
            components.hour = daySchedule.startHour
            components.minute = daySchedule.startMinute
            components.second = 0

            guard let activationDate = calendar.date(from: components) else {
                continue
            }

            if activationDate > now {
                return activationDate
            }
        }

        return nil
    }

    func nextDeactivation() -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // If we're currently active, return today's end time
        if isActiveNow() {
            let weekday = calendar.component(.weekday, from: now)
            guard let currentDay = DayOfWeek.from(calendarWeekday: weekday) else {
                return nil
            }

            let todaySchedule = scheduleFor(day: currentDay)

            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = todaySchedule.endHour
            components.minute = todaySchedule.endMinute
            components.second = 0
            return calendar.date(from: components)
        }

        return nil
    }

    // Helper for summary display
    var summaryDescription: String {
        let enabledDays = DayOfWeek.allCases.filter { scheduleFor(day: $0).enabled }

        if enabledDays.isEmpty {
            return "No days scheduled"
        }

        // Check if all days have the same schedule
        let firstSchedule = scheduleFor(day: enabledDays[0])
        let allSame = enabledDays.allSatisfy { scheduleFor(day: $0) == firstSchedule }

        if allSame {
            let daysStr = formatDaysList(enabledDays)
            return "\(daysStr): \(firstSchedule.startTimeString) - \(firstSchedule.endTimeString)"
        } else {
            return formatCustomSchedule(enabledDays)
        }
    }

    // Format custom schedule in a compact, readable way
    private func formatCustomSchedule(_ enabledDays: [DayOfWeek]) -> String {
        // Group days by their schedule times, preserving order
        var scheduleGroups: [(timeRange: String, days: [DayOfWeek])] = []
        var seenTimeRanges: [String: Int] = [:]

        // Process days in canonical order (Mon-Sun)
        let orderedDays: [DayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

        for day in orderedDays {
            guard enabledDays.contains(day) else { continue }

            let schedule = scheduleFor(day: day)
            let timeKey = "\(schedule.startTimeString)-\(schedule.endTimeString)"

            if let existingIndex = seenTimeRanges[timeKey] {
                scheduleGroups[existingIndex].days.append(day)
            } else {
                seenTimeRanges[timeKey] = scheduleGroups.count
                scheduleGroups.append((timeRange: timeKey, days: [day]))
            }
        }

        // Build the description
        let parts = scheduleGroups.map { group -> String in
            let dayAbbrevs = group.days.map { $0.shortName.prefix(2) }.joined(separator: ",")
            return "\(dayAbbrevs) \(group.timeRange)"
        }

        return parts.joined(separator: " · ")
    }

    private func formatDaysList(_ days: [DayOfWeek]) -> String {
        if days.count == 7 {
            return "Every day"
        }

        let weekdays: [DayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let weekends: [DayOfWeek] = [.saturday, .sunday]

        if Set(days) == Set(weekdays) {
            return "Weekdays"
        } else if Set(days) == Set(weekends) {
            return "Weekends"
        }

        return days.map { $0.shortName }.joined(separator: ", ")
    }
}

// MARK: - Day of Week
enum DayOfWeek: String, Codable, CaseIterable, Identifiable, Hashable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var fullName: String {
        rawValue.capitalized
    }

    // Convert from Calendar.component(.weekday) which returns 1=Sunday, 2=Monday, etc.
    static func from(calendarWeekday: Int) -> DayOfWeek? {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }
}

// MARK: - Blocking Status
enum BlockingStatus: Equatable {
    case active
    case inactive
    case scheduledFor(Date)
    case manualOverride
    case error(String)

    var description: String {
        switch self {
        case .active:
            return "Blocking Active"
        case .inactive:
            return "Blocking Inactive"
        case .scheduledFor(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE HH:mm"
            return "Next: \(formatter.string(from: date))"
        case .manualOverride:
            return "Manual Override"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isBlocking: Bool {
        switch self {
        case .active, .manualOverride:
            return true
        default:
            return false
        }
    }
}
