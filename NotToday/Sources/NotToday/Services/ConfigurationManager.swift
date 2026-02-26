import Foundation

class ConfigurationManager: ObservableObject {
    static let shared = ConfigurationManager()

    @Published var configuration: Configuration {
        didSet {
            saveConfiguration()
        }
    }

    private let configURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        // Store config in Application Support folder
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("NotToday", isDirectory: true)

        // Create app folder if it doesn't exist
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        self.configURL = appFolder.appendingPathComponent("config.json")

        // Try to load existing configuration
        if let data = try? Data(contentsOf: configURL),
           let config = try? decoder.decode(Configuration.self, from: data) {
            self.configuration = config
        } else {
            // Use default configuration
            self.configuration = Configuration.defaultConfig
            saveConfiguration()
        }

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func saveConfiguration() {
        guard let data = try? encoder.encode(configuration) else {
            print("Failed to encode configuration")
            return
        }

        do {
            try data.write(to: configURL, options: .atomic)
            print("Configuration saved to: \(configURL.path)")
        } catch {
            print("Failed to save configuration: \(error)")
        }
    }

    func loadConfiguration() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? decoder.decode(Configuration.self, from: data) else {
            return
        }
        configuration = config
    }

    func resetToDefaults() {
        configuration = Configuration.defaultConfig
    }

    // MARK: - Site Management

    func addSite(_ site: String) {
        var normalizedSite = site.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove protocol if present
        if normalizedSite.hasPrefix("https://") {
            normalizedSite = String(normalizedSite.dropFirst(8))
        } else if normalizedSite.hasPrefix("http://") {
            normalizedSite = String(normalizedSite.dropFirst(7))
        }

        // Remove trailing slash
        if normalizedSite.hasSuffix("/") {
            normalizedSite = String(normalizedSite.dropLast())
        }

        guard !normalizedSite.isEmpty,
              !configuration.blockedSites.contains(normalizedSite) else {
            return
        }

        configuration.blockedSites.append(normalizedSite)

        // Also add www variant if not present
        if !normalizedSite.hasPrefix("www.") {
            let wwwVariant = "www." + normalizedSite
            if !configuration.blockedSites.contains(wwwVariant) {
                configuration.blockedSites.append(wwwVariant)
            }
        }

        // If blocking is currently active, re-apply to include the new site
        refreshBlockingIfActive()
    }

    /// Re-applies blocking if currently active to include any new sites
    func refreshBlockingIfActive() {
        if BlockingService.shared.isBlocking {
            BlockingService.shared.activateBlocking(sites: configuration.blockedSites)
        }
    }

    func removeSite(_ site: String) {
        configuration.blockedSites.removeAll { $0 == site }
    }

    func removeSites(at offsets: IndexSet) {
        configuration.blockedSites.remove(atOffsets: offsets)
    }

    // MARK: - Schedule Management

    func updateDaySchedule(day: DayOfWeek, schedule: DaySchedule) {
        var currentSchedule = configuration.schedule
        currentSchedule.daySchedules[day] = schedule
        configuration.schedule = currentSchedule
    }

    func toggleDay(_ day: DayOfWeek) {
        var daySchedule = configuration.schedule.scheduleFor(day: day)
        daySchedule.enabled.toggle()
        updateDaySchedule(day: day, schedule: daySchedule)
    }

    /// Legacy method - updates the first time range only
    func updateDayTime(day: DayOfWeek, startHour: Int? = nil, startMinute: Int? = nil, endHour: Int? = nil, endMinute: Int? = nil) {
        var daySchedule = configuration.schedule.scheduleFor(day: day)

        guard !daySchedule.timeRanges.isEmpty else { return }

        var range = daySchedule.timeRanges[0]
        if let startHour = startHour {
            range.startHour = max(0, min(23, startHour))
        }
        if let startMinute = startMinute {
            range.startMinute = max(0, min(59, startMinute))
        }
        if let endHour = endHour {
            range.endHour = max(0, min(23, endHour))
        }
        if let endMinute = endMinute {
            range.endMinute = max(0, min(59, endMinute))
        }
        daySchedule.timeRanges[0] = range

        updateDaySchedule(day: day, schedule: daySchedule)
    }

    // MARK: - Time Range Management

    /// Update a specific time range for a day
    func updateTimeRange(day: DayOfWeek, rangeIndex: Int, range: TimeRange) {
        var daySchedule = configuration.schedule.scheduleFor(day: day)
        guard rangeIndex >= 0 && rangeIndex < daySchedule.timeRanges.count else { return }
        daySchedule.timeRanges[rangeIndex] = range
        updateDaySchedule(day: day, schedule: daySchedule)
    }

    /// Add a new time range to a day
    func addTimeRange(day: DayOfWeek) {
        var daySchedule = configuration.schedule.scheduleFor(day: day)

        // Default new range: after last range, or 09:00-12:00 if no ranges
        let newRange: TimeRange
        if let lastRange = daySchedule.timeRanges.last {
            // Start 1 hour after the last range ends
            let newStartHour = min(lastRange.endHour + 1, 23)
            let newEndHour = min(newStartHour + 3, 23)
            newRange = TimeRange(
                startHour: newStartHour,
                startMinute: 0,
                endHour: newEndHour,
                endMinute: 0
            )
        } else {
            newRange = TimeRange(startHour: 9, startMinute: 0, endHour: 12, endMinute: 0)
        }

        daySchedule.timeRanges.append(newRange)
        updateDaySchedule(day: day, schedule: daySchedule)
    }

    /// Remove a time range from a day
    func removeTimeRange(day: DayOfWeek, rangeIndex: Int) {
        var daySchedule = configuration.schedule.scheduleFor(day: day)
        guard rangeIndex >= 0 && rangeIndex < daySchedule.timeRanges.count else { return }

        // Keep at least one range
        if daySchedule.timeRanges.count > 1 {
            daySchedule.timeRanges.remove(at: rangeIndex)
            updateDaySchedule(day: day, schedule: daySchedule)
        }
    }

    /// Get the schedule validation error, if any
    var scheduleValidationError: String? {
        configuration.schedule.validationError
    }

    /// Check if the current schedule is valid
    var isScheduleValid: Bool {
        configuration.schedule.isValid
    }

    // Quick presets
    func applyWeekdaysPreset() {
        for day in DayOfWeek.allCases {
            var schedule = configuration.schedule.scheduleFor(day: day)
            switch day {
            case .monday, .tuesday, .wednesday, .thursday, .friday:
                schedule.enabled = true
            case .saturday, .sunday:
                schedule.enabled = false
            }
            updateDaySchedule(day: day, schedule: schedule)
        }
    }

    func applyWeekendsPreset() {
        for day in DayOfWeek.allCases {
            var schedule = configuration.schedule.scheduleFor(day: day)
            switch day {
            case .saturday, .sunday:
                schedule.enabled = true
            default:
                schedule.enabled = false
            }
            updateDaySchedule(day: day, schedule: schedule)
        }
    }

    func applyEveryDayPreset() {
        for day in DayOfWeek.allCases {
            var schedule = configuration.schedule.scheduleFor(day: day)
            schedule.enabled = true
            updateDaySchedule(day: day, schedule: schedule)
        }
    }

    // MARK: - Config File Location

    var configFilePath: String {
        configURL.path
    }
}
