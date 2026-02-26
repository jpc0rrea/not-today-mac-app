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

// MARK: - Time Range (single blocking period)
struct TimeRange: Codable, Equatable, Identifiable {
    var id: UUID
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(id: UUID = UUID(), startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.id = id
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    var startTimeString: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endTimeString: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    var startMinutes: Int {
        startHour * 60 + startMinute
    }

    var endMinutes: Int {
        endHour * 60 + endMinute
    }

    /// Check if this time range is valid (end time after start time)
    var isValid: Bool {
        endMinutes > startMinutes
    }

    /// Validation error message, or nil if valid
    var validationError: String? {
        if endMinutes <= startMinutes {
            return "End time must be after start time"
        }
        return nil
    }

    /// Check if a given time (in minutes from midnight) is within this range
    func contains(minutes: Int) -> Bool {
        return minutes >= startMinutes && minutes < endMinutes
    }

    static let defaultMorning = TimeRange(
        startHour: 9,
        startMinute: 0,
        endHour: 12,
        endMinute: 0
    )

    static let defaultAfternoon = TimeRange(
        startHour: 14,
        startMinute: 0,
        endHour: 18,
        endMinute: 0
    )

    static let defaultFullDay = TimeRange(
        startHour: 9,
        startMinute: 0,
        endHour: 19,
        endMinute: 0
    )
}

// MARK: - Day Schedule (per-day time configuration with multiple ranges)
struct DaySchedule: Codable, Equatable {
    var enabled: Bool
    var timeRanges: [TimeRange]

    // MARK: - Initializers

    /// Initialize with multiple time ranges
    init(enabled: Bool, timeRanges: [TimeRange]) {
        self.enabled = enabled
        self.timeRanges = timeRanges
    }

    /// Legacy initializer for backward compatibility
    init(enabled: Bool, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.enabled = enabled
        self.timeRanges = [TimeRange(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute
        )]
    }

    // MARK: - Codable (handles both old and new format)

    enum CodingKeys: String, CodingKey {
        case enabled
        case timeRanges
        // Legacy keys
        case startHour, startMinute, endHour, endMinute
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)

        // Try new format first
        if let ranges = try? container.decode([TimeRange].self, forKey: .timeRanges) {
            timeRanges = ranges
        } else {
            // Fall back to legacy format
            let startHour = try container.decode(Int.self, forKey: .startHour)
            let startMinute = try container.decode(Int.self, forKey: .startMinute)
            let endHour = try container.decode(Int.self, forKey: .endHour)
            let endMinute = try container.decode(Int.self, forKey: .endMinute)
            timeRanges = [TimeRange(
                startHour: startHour,
                startMinute: startMinute,
                endHour: endHour,
                endMinute: endMinute
            )]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(timeRanges, forKey: .timeRanges)
    }

    // MARK: - Computed Properties

    /// Check if all time ranges are valid
    var isValid: Bool {
        timeRanges.allSatisfy { $0.isValid }
    }

    /// Get first validation error, or nil if all valid
    var validationError: String? {
        for range in timeRanges {
            if let error = range.validationError {
                return error
            }
        }
        // Check for overlapping ranges
        return overlappingRangesError
    }

    /// Check if any ranges overlap
    private var overlappingRangesError: String? {
        let sortedRanges = timeRanges.sorted { $0.startMinutes < $1.startMinutes }
        for i in 0..<sortedRanges.count - 1 {
            if sortedRanges[i].endMinutes > sortedRanges[i + 1].startMinutes {
                return "Time ranges cannot overlap"
            }
        }
        return nil
    }

    /// Legacy property for backward compatibility
    var startHour: Int {
        timeRanges.first?.startHour ?? 9
    }

    var startMinute: Int {
        timeRanges.first?.startMinute ?? 0
    }

    var endHour: Int {
        timeRanges.first?.endHour ?? 17
    }

    var endMinute: Int {
        timeRanges.first?.endMinute ?? 0
    }

    var startTimeString: String {
        timeRanges.first?.startTimeString ?? "09:00"
    }

    var endTimeString: String {
        timeRanges.first?.endTimeString ?? "17:00"
    }

    // MARK: - Defaults

    static let defaultWeekday = DaySchedule(
        enabled: true,
        timeRanges: [TimeRange.defaultFullDay]
    )

    static let defaultWeekend = DaySchedule(
        enabled: false,
        timeRanges: [TimeRange(startHour: 10, startMinute: 0, endHour: 14, endMinute: 0)]
    )

    static let disabled = DaySchedule(
        enabled: false,
        timeRanges: [TimeRange(startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)]
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

    /// Check if current time is within any scheduled time range for today
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

        // Check if current time is within any of the scheduled time ranges
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        return todaySchedule.timeRanges.contains { range in
            range.contains(minutes: currentMinutes)
        }
    }

    /// Get the current active time range, if any
    func currentActiveRange() -> TimeRange? {
        let calendar = Calendar.current
        let now = Date()

        let weekday = calendar.component(.weekday, from: now)
        guard let currentDay = DayOfWeek.from(calendarWeekday: weekday) else {
            return nil
        }

        let todaySchedule = scheduleFor(day: currentDay)
        guard todaySchedule.enabled else { return nil }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        return todaySchedule.timeRanges.first { range in
            range.contains(minutes: currentMinutes)
        }
    }

    func currentDayEndTime() -> String? {
        guard let activeRange = currentActiveRange() else {
            return nil
        }
        return activeRange.endTimeString
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

            // Check each time range
            for range in daySchedule.timeRanges.sorted(by: { $0.startMinutes < $1.startMinutes }) {
                var components = calendar.dateComponents([.year, .month, .day], from: checkDate)
                components.hour = range.startHour
                components.minute = range.startMinute
                components.second = 0

                guard let activationDate = calendar.date(from: components) else {
                    continue
                }

                if activationDate > now {
                    return activationDate
                }
            }
        }

        return nil
    }

    func nextDeactivation() -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // If we're currently active, return the end time of the current range
        if let activeRange = currentActiveRange() {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = activeRange.endHour
            components.minute = activeRange.endMinute
            components.second = 0
            return calendar.date(from: components)
        }

        return nil
    }

    // MARK: - Validation

    /// Check if all day schedules are valid
    var isValid: Bool {
        daySchedules.values.allSatisfy { $0.isValid }
    }

    /// Get first validation error, or nil if all valid
    var validationError: String? {
        for (day, schedule) in daySchedules {
            if let error = schedule.validationError {
                return "\(day.shortName): \(error)"
            }
        }
        return nil
    }

    // MARK: - Summary Display

    var summaryDescription: String {
        let enabledDays = DayOfWeek.allCases.filter { scheduleFor(day: $0).enabled }

        if enabledDays.isEmpty {
            return "No days scheduled"
        }

        // Build a description showing all time ranges
        return formatCustomSchedule(enabledDays)
    }

    private func formatCustomSchedule(_ enabledDays: [DayOfWeek]) -> String {
        let orderedDays: [DayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

        var parts: [String] = []
        for day in orderedDays {
            guard enabledDays.contains(day) else { continue }
            let schedule = scheduleFor(day: day)

            let rangeStrings = schedule.timeRanges.map { "\($0.startTimeString)-\($0.endTimeString)" }
            let dayAbbrev = String(day.shortName.prefix(2))
            parts.append("\(dayAbbrev) \(rangeStrings.joined(separator: ", "))")
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
