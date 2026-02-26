import Foundation
import Combine
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.nottoday.app", category: "ScheduleManager")

class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()

    @Published var isScheduleActive: Bool = false
    @Published var manualOverride: Bool = false
    @Published var nextScheduledEvent: String = ""
    @Published var sessionEndTime: Date? = nil
    @Published var remainingTime: String = ""

    /// Flag to track if there are pending schedule changes to sync when session ends
    var hasPendingScheduleChanges: Bool = false

    /// Track previous blocking state to detect transitions for notifications
    private var previousBlockingState: Bool = false

    private var timer: Timer?
    private var countdownTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let configManager = ConfigurationManager.shared
    private let blockingService = BlockingService.shared

    init() {
        startMonitoring()
        updateStatus()
        setupConfigurationObserver()
    }

    // MARK: - Notifications

    func sendSessionStartNotification(minutes: Int) {
        sendNotification(
            title: "Focus Session Started",
            body: "Blocking is now active for \(minutes) minutes. Stay focused!"
        )
    }

    private func sendNotification(title: String, body: String) {
        // Check permission status first
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            logger.info("Notification auth status: \(settings.authorizationStatus.rawValue)")

            if settings.authorizationStatus == .authorized {
                // Permission granted - send notification
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: trigger
                )

                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        logger.error("Notification error: \(error.localizedDescription)")
                    } else {
                        logger.info("Notification sent: \(title)")
                    }
                }
            } else if settings.authorizationStatus == .notDetermined {
                // Request permission again
                logger.info("Notification permission not determined, requesting...")
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        // Try again after permission granted
                        self.sendNotification(title: title, body: body)
                    }
                }
            } else {
                logger.warning("Notifications not authorized (status: \(settings.authorizationStatus.rawValue))")
            }
        }
    }

    func sendSessionEndNotification() {
        sendNotification(
            title: "Focus Session Ended",
            body: "Great work! Your blocking session has ended."
        )
    }

    func sendScheduledBlockingStartNotification() {
        sendNotification(
            title: "Scheduled Blocking Active",
            body: "Your scheduled focus time has started. Distracting sites are now blocked."
        )
    }

    func sendScheduledBlockingEndNotification() {
        sendNotification(
            title: "Scheduled Blocking Ended",
            body: "Your scheduled focus time has ended."
        )
    }

    // MARK: - Pending Changes Sync

    private func syncPendingChangesIfNeeded() {
        guard hasPendingScheduleChanges else { return }

        print("Syncing pending schedule changes to helper...")
        blockingService.syncScheduleToHelper(configuration: configManager.configuration)
        hasPendingScheduleChanges = false
    }

    // MARK: - Configuration Observer

    /// Watch for configuration changes and sync to helper
    private func setupConfigurationObserver() {
        configManager.$configuration
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] configuration in
                self?.handleConfigurationChange(configuration: configuration)
            }
            .store(in: &cancellables)
    }

    /// Handle configuration changes - only sync if not currently blocking
    private func handleConfigurationChange(configuration: Configuration) {
        // Don't auto-sync during active blocking session - user must explicitly save
        // and changes will be applied after session ends
        if blockingService.isBlocking {
            print("Configuration changed during active session - will sync after session ends")
            return
        }

        blockingService.syncScheduleToHelper(configuration: configuration)
    }

    // MARK: - Monitoring

    func startMonitoring() {
        // Check every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndUpdateBlocking()
        }

        // Also check immediately
        checkAndUpdateBlocking()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Status Updates

    func updateStatus() {
        let schedule = configManager.configuration.schedule

        if !configManager.configuration.enabled {
            nextScheduledEvent = "Scheduling disabled"
            return
        }

        if schedule.isActiveNow() {
            isScheduleActive = true
            if let endTime = schedule.nextDeactivation() {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                nextScheduledEvent = "Ends at \(formatter.string(from: endTime))"
            }
        } else {
            isScheduleActive = false
            if let nextStart = schedule.nextActivation() {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE HH:mm"
                nextScheduledEvent = "Starts \(formatter.string(from: nextStart))"
            } else {
                nextScheduledEvent = "No upcoming schedule"
            }
        }
    }

    // MARK: - Blocking Control

    func checkAndUpdateBlocking() {
        guard configManager.configuration.enabled else {
            checkForBlockingStateChange()
            updateStatus()
            return
        }

        let schedule = configManager.configuration.schedule
        let shouldBlock = schedule.isActiveNow()

        // Don't change anything if manual override is active
        if manualOverride {
            updateStatus()
            return
        }

        // If helper is installed, it handles schedule-based blocking automatically
        // We just need to sync the status and check for state changes
        if HelperInstaller.shared.isHelperInstalled {
            blockingService.syncBlockingStatus()
            checkForBlockingStateChange()
            updateStatus()
            return
        }

        // Fallback: When helper is NOT installed, use the AppleScript approach
        let currentlyBlocking = blockingService.isBlocking

        if shouldBlock && !currentlyBlocking {
            // Activate blocking with scheduled end time (single password prompt)
            if let endTime = schedule.nextDeactivation() {
                // Calculate minutes until scheduled end
                let minutesUntilEnd = Int(endTime.timeIntervalSinceNow / 60)
                if minutesUntilEnd > 0 {
                    blockingService.activateBlockingWithScheduledEnd(
                        sites: configManager.configuration.blockedSites,
                        minutes: minutesUntilEnd
                    ) { [weak self] success in
                        if success {
                            self?.checkForBlockingStateChange()
                            self?.updateStatus()
                        }
                    }
                }
            } else {
                // Fallback to regular activation if no end time found
                blockingService.activateBlocking(sites: configManager.configuration.blockedSites)
            }
        } else if !shouldBlock && currentlyBlocking {
            // Deactivation should happen automatically via the scheduled script
            // But sync the status in case it already ran
            blockingService.syncBlockingStatus()
        }

        checkForBlockingStateChange()
        updateStatus()
    }

    /// Check if blocking state changed and send notification for scheduled blocking
    private func checkForBlockingStateChange() {
        let currentlyBlocking = blockingService.isBlocking

        // Only send notifications for scheduled blocking (not manual focus sessions)
        // Manual focus sessions send their own notifications
        if !manualOverride && sessionEndTime == nil {
            if currentlyBlocking && !previousBlockingState {
                // Blocking just started (scheduled)
                sendScheduledBlockingStartNotification()

                // Sync any pending changes now that a new session started
                // (they'll take effect after this session ends anyway)
            } else if !currentlyBlocking && previousBlockingState {
                // Blocking just ended (scheduled)
                sendScheduledBlockingEndNotification()

                // Sync any pending schedule changes now that session ended
                syncPendingChangesIfNeeded()
            }
        }

        previousBlockingState = currentlyBlocking
    }

    // MARK: - Manual Override

    func enableManualOverride(block: Bool) {
        manualOverride = true

        if block {
            blockingService.activateBlocking(sites: configManager.configuration.blockedSites)
        } else {
            blockingService.deactivateBlocking()
        }
    }

    func disableManualOverride() {
        manualOverride = false
        checkAndUpdateBlocking()
    }

    // MARK: - Force Actions

    func forceActivate() {
        blockingService.activateBlocking(sites: configManager.configuration.blockedSites)
    }

    func forceDeactivate() {
        blockingService.deactivateBlocking()
    }

    // MARK: - Quick Actions

    func blockForDuration(minutes: Int) {
        // Validate duration
        guard minutes > 0 else {
            print("Invalid duration: \(minutes) minutes")
            return
        }

        // Use the new method that schedules deactivation in one password prompt
        print("Starting focus session for \(minutes) minutes")
        blockingService.activateBlockingWithScheduledEnd(
            sites: configManager.configuration.blockedSites,
            minutes: minutes
        ) { [weak self] success in
            print("Focus session activation completed: \(success)")
            guard let self = self else {
                print("Self was nil in completion")
                return
            }

            if success {
                // Only set session state AFTER successful authentication
                let endTime = Date().addingTimeInterval(Double(minutes * 60))
                self.sessionEndTime = endTime
                self.manualOverride = true

                // Start countdown timer only after password accepted
                self.startCountdownTimer()

                // Send notification that session started
                self.sendSessionStartNotification(minutes: minutes)

                print("Focus session started successfully")
                // Notify that blocking status changed
                NotificationCenter.default.post(name: NSNotification.Name("BlockingStatusChanged"), object: nil)

                // Schedule UI update when session ends
                // Note: Actual deactivation is handled by LaunchDaemon - no password needed
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes * 60) + 5) { [weak self] in
                    guard let self = self else { return }

                    self.sessionEndTime = nil
                    self.remainingTime = ""
                    self.stopCountdownTimer()
                    self.manualOverride = false

                    // Send notification that session ended
                    self.sendSessionEndNotification()

                    // Sync any pending schedule changes now that session is over
                    self.syncPendingChangesIfNeeded()

                    // Sync status from hosts file (LaunchDaemon should have deactivated)
                    self.blockingService.syncBlockingStatus()
                    self.updateStatus()

                    // Notify UI about the change
                    NotificationCenter.default.post(name: NSNotification.Name("BlockingStatusChanged"), object: nil)
                }
            } else {
                print("Focus session failed to start")
                // Reset state on failure
                self.sessionEndTime = nil
                self.remainingTime = ""
                self.manualOverride = false
            }
        }
    }

    func unblockForDuration(minutes: Int) {
        enableManualOverride(block: false)

        // Schedule automatic reblock
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes * 60)) { [weak self] in
            self?.disableManualOverride()
        }
    }

    // MARK: - Countdown Timer

    private func startCountdownTimer() {
        stopCountdownTimer()
        updateRemainingTime()

        // Create timer and explicitly add to main run loop with .common mode
        // This ensures it fires even when called from completion handlers
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateRemainingTime()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateRemainingTime() {
        guard let endTime = sessionEndTime else {
            remainingTime = ""
            return
        }

        let now = Date()
        let remaining = endTime.timeIntervalSince(now)

        if remaining <= 0 {
            remainingTime = ""
            sessionEndTime = nil
            stopCountdownTimer()
            return
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            remainingTime = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            remainingTime = String(format: "%d:%02d", minutes, seconds)
        }
    }
}
