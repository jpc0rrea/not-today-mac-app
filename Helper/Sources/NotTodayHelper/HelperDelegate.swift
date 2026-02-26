import Foundation

// MARK: - XPC Listener Delegate

class HelperDelegate: NSObject, NSXPCListenerDelegate {

    // Singleton service that persists across connections
    let service = HelperService.shared

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: NotTodayHelperProtocol.self)
        newConnection.exportedObject = service

        newConnection.invalidationHandler = {
            // Connection was invalidated
        }

        newConnection.interruptionHandler = {
            // Connection was interrupted
        }

        newConnection.resume()
        return true
    }
}

// MARK: - Helper Service Implementation (Singleton)

class HelperService: NSObject, NotTodayHelperProtocol {

    static let shared = HelperService()

    private let hostsPath = HelperConstants.hostsFilePath
    private let configPath = HelperConstants.helperConfigPath
    private var scheduleTimer: Timer?
    private var currentConfig: HelperScheduleConfig?

    override init() {
        super.init()
        loadConfiguration()
        startScheduleMonitoring()
        print("HelperService initialized, schedule monitoring started")
    }

    // MARK: - Configuration Persistence

    private func loadConfiguration() {
        let configURL = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(HelperScheduleConfig.self, from: data) else {
            print("HelperService: No config found or failed to decode")
            return
        }
        currentConfig = config
        print("HelperService: Loaded config with \(config.blockedSites.count) sites")
    }

    private func saveConfiguration() {
        guard let config = currentConfig else { return }

        let configURL = URL(fileURLWithPath: configPath)
        let directory = configURL.deletingLastPathComponent()

        // Create directory if needed
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL, options: .atomic)
            print("HelperService: Config saved")
        }
    }

    // MARK: - Schedule Monitoring

    private func startScheduleMonitoring() {
        // Ensure we're on the main thread for timer
        if Thread.isMainThread {
            setupTimer()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setupTimer()
            }
        }
    }

    private func setupTimer() {
        scheduleTimer?.invalidate()

        // Check schedule every 30 seconds
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }

        // Add to common run loop mode to ensure it fires
        if let timer = scheduleTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        // Also check immediately
        checkSchedule()
        print("HelperService: Schedule timer started")
    }

    private func checkSchedule() {
        guard let config = currentConfig, config.enabled else {
            print("HelperService: Schedule check - no config or disabled")
            return
        }

        let shouldBlock = isWithinSchedule(config: config)
        let currentlyBlocking = checkHostsFileBlocking()

        print("HelperService: Schedule check - shouldBlock=\(shouldBlock), currentlyBlocking=\(currentlyBlocking)")

        if shouldBlock && !currentlyBlocking {
            print("HelperService: Activating blocking based on schedule")
            performActivateBlocking(sites: config.blockedSites)
        } else if !shouldBlock && currentlyBlocking {
            print("HelperService: Deactivating blocking based on schedule")
            performDeactivateBlocking()
        }
    }

    private func isWithinSchedule(config: HelperScheduleConfig) -> Bool {
        let calendar = Calendar.current
        let now = Date()

        let weekday = calendar.component(.weekday, from: now)
        let dayKey = dayKeyFromWeekday(weekday)

        guard let daySchedule = config.daySchedules[dayKey], daySchedule.enabled else {
            return false
        }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        // Check all time ranges for this day
        for range in daySchedule.timeRanges {
            let startMinutes = range.startMinutes
            let endMinutes = range.endMinutes

            if currentMinutes >= startMinutes && currentMinutes < endMinutes {
                print("HelperService: \(dayKey) - current=\(currentMinutes), in range \(startMinutes)-\(endMinutes)")
                return true
            }
        }

        print("HelperService: \(dayKey) - current=\(currentMinutes), not in any of \(daySchedule.timeRanges.count) ranges")
        return false
    }

    private func dayKeyFromWeekday(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "sunday"
        case 2: return "monday"
        case 3: return "tuesday"
        case 4: return "wednesday"
        case 5: return "thursday"
        case 6: return "friday"
        case 7: return "saturday"
        default: return "monday"
        }
    }

    // MARK: - Hosts File Operations

    private func checkHostsFileBlocking() -> Bool {
        guard let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return false
        }
        return content.contains(HelperConstants.blockMarkerStart)
    }

    private func performActivateBlocking(sites: [String]) {
        guard !sites.isEmpty else {
            print("HelperService: No sites to block")
            return
        }

        do {
            var hostsContent = try String(contentsOfFile: hostsPath, encoding: .utf8)

            // Remove existing NotToday entries
            hostsContent = removeNotTodaySection(from: hostsContent)

            // Build new block entries
            let blockEntries = sites.map { "127.0.0.1 \($0)" }.joined(separator: "\n")
            let blockSection = """

            \(HelperConstants.blockMarkerStart)
            \(blockEntries)
            \(HelperConstants.blockMarkerEnd)
            """

            hostsContent += blockSection

            // Write back to hosts file
            try hostsContent.write(toFile: hostsPath, atomically: true, encoding: .utf8)

            // Flush DNS cache
            flushDNSCache()

            print("HelperService: Blocking activated for \(sites.count) sites")

        } catch {
            print("HelperService: Failed to activate blocking: \(error)")
        }
    }

    private func performDeactivateBlocking() {
        do {
            var hostsContent = try String(contentsOfFile: hostsPath, encoding: .utf8)

            // Remove NotToday entries
            hostsContent = removeNotTodaySection(from: hostsContent)

            // Write back to hosts file
            try hostsContent.write(toFile: hostsPath, atomically: true, encoding: .utf8)

            // Flush DNS cache
            flushDNSCache()

            print("HelperService: Blocking deactivated")

        } catch {
            print("HelperService: Failed to deactivate blocking: \(error)")
        }
    }

    private func removeNotTodaySection(from content: String) -> String {
        var result = content
        let pattern = "\n?\(NSRegularExpression.escapedPattern(for: HelperConstants.blockMarkerStart)).*?\(NSRegularExpression.escapedPattern(for: HelperConstants.blockMarkerEnd))"

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        return result
    }

    private func flushDNSCache() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]
        try? process.run()
        process.waitUntilExit()

        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProcess.arguments = ["-HUP", "mDNSResponder"]
        try? killProcess.run()
        killProcess.waitUntilExit()
    }

    private func getBlockedSitesFromHosts() -> [String] {
        guard let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return []
        }

        var sites: [String] = []
        var inBlockSection = false

        for line in content.components(separatedBy: .newlines) {
            if line.contains(HelperConstants.blockMarkerStart) {
                inBlockSection = true
                continue
            }
            if line.contains(HelperConstants.blockMarkerEnd) {
                inBlockSection = false
                continue
            }
            if inBlockSection && line.starts(with: "127.0.0.1") {
                let components = line.components(separatedBy: .whitespaces)
                if components.count >= 2 {
                    sites.append(components[1])
                }
            }
        }

        return sites
    }

    // MARK: - Protocol Implementation

    func activateBlocking(sites: [String], reply: @escaping (Bool, String?) -> Void) {
        print("HelperService: activateBlocking called with \(sites.count) sites")
        performActivateBlocking(sites: sites)
        let success = checkHostsFileBlocking()
        print("HelperService: activateBlocking result: \(success)")
        reply(success, success ? nil : "Failed to verify blocking was applied")
    }

    func deactivateBlocking(reply: @escaping (Bool, String?) -> Void) {
        print("HelperService: deactivateBlocking called")
        performDeactivateBlocking()
        let success = !checkHostsFileBlocking()
        print("HelperService: deactivateBlocking result: \(success)")
        reply(success, success ? nil : "Failed to verify blocking was removed")
    }

    func isBlockingActive(reply: @escaping (Bool) -> Void) {
        let isActive = checkHostsFileBlocking()
        print("HelperService: isBlockingActive = \(isActive)")
        reply(isActive)
    }

    func getBlockedSites(reply: @escaping ([String]) -> Void) {
        reply(getBlockedSitesFromHosts())
    }

    func updateSchedule(scheduleData: Data, sites: [String], reply: @escaping (Bool, String?) -> Void) {
        print("HelperService: updateSchedule called")
        do {
            var config = try JSONDecoder().decode(HelperScheduleConfig.self, from: scheduleData)
            config.blockedSites = sites
            currentConfig = config
            saveConfiguration()

            // Immediately check if we should activate/deactivate based on new schedule
            checkSchedule()

            reply(true, nil)
        } catch {
            print("HelperService: updateSchedule failed: \(error)")
            reply(false, "Failed to decode schedule: \(error.localizedDescription)")
        }
    }

    func setScheduleEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        if var config = currentConfig {
            config.enabled = enabled
            currentConfig = config
            saveConfiguration()

            // Check schedule immediately
            checkSchedule()

            reply(true, nil)
        } else {
            reply(false, "No configuration loaded")
        }
    }

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply(HelperConstants.helperVersion)
    }

    func uninstallHelper(reply: @escaping (Bool, String?) -> Void) {
        // Deactivate blocking first
        performDeactivateBlocking()

        // Remove our config file
        try? FileManager.default.removeItem(atPath: configPath)

        reply(true, nil)

        // Exit after a short delay to allow the reply to be sent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }
}
