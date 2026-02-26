import Foundation

// MARK: - XPC Protocol
// This protocol defines the interface between the main app and the privileged helper

/// Protocol for the privileged helper that runs as root
@objc(NotTodayHelperProtocol)
public protocol NotTodayHelperProtocol {

    /// Activate blocking by adding entries to /etc/hosts
    /// - Parameters:
    ///   - sites: Array of sites to block (e.g., ["twitter.com", "www.twitter.com"])
    ///   - reply: Callback with success status and optional error message
    func activateBlocking(sites: [String], reply: @escaping (Bool, String?) -> Void)

    /// Deactivate blocking by removing entries from /etc/hosts
    /// - Parameter reply: Callback with success status and optional error message
    func deactivateBlocking(reply: @escaping (Bool, String?) -> Void)

    /// Check if blocking is currently active
    /// - Parameter reply: Callback with blocking status
    func isBlockingActive(reply: @escaping (Bool) -> Void)

    /// Get the list of currently blocked sites from /etc/hosts
    /// - Parameter reply: Callback with array of blocked sites
    func getBlockedSites(reply: @escaping ([String]) -> Void)

    /// Update the helper's stored schedule configuration
    /// - Parameters:
    ///   - scheduleData: JSON-encoded schedule data
    ///   - sites: Array of sites to block when schedule is active
    ///   - reply: Callback with success status
    func updateSchedule(scheduleData: Data, sites: [String], reply: @escaping (Bool, String?) -> Void)

    /// Enable or disable schedule-based automatic blocking
    /// - Parameters:
    ///   - enabled: Whether schedule-based blocking should be active
    ///   - reply: Callback with success status
    func setScheduleEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void)

    /// Get the helper version for compatibility checking
    /// - Parameter reply: Callback with version string
    func getHelperVersion(reply: @escaping (String) -> Void)

    /// Uninstall the helper (remove itself)
    /// - Parameter reply: Callback with success status
    func uninstallHelper(reply: @escaping (Bool, String?) -> Void)
}

// MARK: - Helper Constants

public struct HelperConstants {
    /// Bundle identifier for the privileged helper
    public static let helperBundleIdentifier = "com.nottoday.helper"

    /// Mach service name for XPC connection
    public static let machServiceName = "com.nottoday.helper"

    /// Path where the helper will be installed
    public static let helperInstallPath = "/Library/PrivilegedHelperTools/com.nottoday.helper"

    /// Path for the helper's launchd plist
    public static let launchdPlistPath = "/Library/LaunchDaemons/com.nottoday.helper.plist"

    /// Path for the helper's configuration storage
    public static let helperConfigPath = "/Library/Application Support/NotToday/helper-config.json"

    /// Current helper version
    public static let helperVersion = "1.0.0"

    /// Hosts file path
    public static let hostsFilePath = "/etc/hosts"

    /// Marker strings for the hosts file
    public static let blockMarkerStart = "# NotToday START - DO NOT EDIT THIS SECTION"
    public static let blockMarkerEnd = "# NotToday END"
}

// MARK: - Schedule Data Transfer Object

/// Codable structure to transfer schedule configuration via XPC
public struct HelperScheduleConfig: Codable {
    public var daySchedules: [String: HelperDaySchedule]
    public var enabled: Bool
    public var blockedSites: [String]

    public init(daySchedules: [String: HelperDaySchedule], enabled: Bool, blockedSites: [String]) {
        self.daySchedules = daySchedules
        self.enabled = enabled
        self.blockedSites = blockedSites
    }
}

public struct HelperTimeRange: Codable {
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int

    public var startMinutes: Int {
        startHour * 60 + startMinute
    }

    public var endMinutes: Int {
        endHour * 60 + endMinute
    }

    public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }
}

public struct HelperDaySchedule: Codable {
    public var enabled: Bool
    public var timeRanges: [HelperTimeRange]

    // Legacy properties for backward compatibility
    public var startHour: Int {
        timeRanges.first?.startHour ?? 9
    }
    public var startMinute: Int {
        timeRanges.first?.startMinute ?? 0
    }
    public var endHour: Int {
        timeRanges.first?.endHour ?? 17
    }
    public var endMinute: Int {
        timeRanges.first?.endMinute ?? 0
    }

    // MARK: - Codable (handles both old and new format)

    enum CodingKeys: String, CodingKey {
        case enabled
        case timeRanges
        // Legacy keys
        case startHour, startMinute, endHour, endMinute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)

        // Try new format first
        if let ranges = try? container.decode([HelperTimeRange].self, forKey: .timeRanges) {
            timeRanges = ranges
        } else {
            // Fall back to legacy format
            let startHour = try container.decode(Int.self, forKey: .startHour)
            let startMinute = try container.decode(Int.self, forKey: .startMinute)
            let endHour = try container.decode(Int.self, forKey: .endHour)
            let endMinute = try container.decode(Int.self, forKey: .endMinute)
            timeRanges = [HelperTimeRange(
                startHour: startHour,
                startMinute: startMinute,
                endHour: endHour,
                endMinute: endMinute
            )]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(timeRanges, forKey: .timeRanges)
    }

    public init(enabled: Bool, timeRanges: [HelperTimeRange]) {
        self.enabled = enabled
        self.timeRanges = timeRanges
    }

    /// Legacy initializer for backward compatibility
    public init(enabled: Bool, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.enabled = enabled
        self.timeRanges = [HelperTimeRange(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute
        )]
    }
}
