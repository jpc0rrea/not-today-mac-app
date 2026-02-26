import SwiftUI

struct MenuBarView: View {
    @ObservedObject var blockingService = BlockingService.shared
    @ObservedObject var scheduleManager = ScheduleManager.shared
    @ObservedObject var configManager = ConfigurationManager.shared
    @ObservedObject var licenseManager = LicenseManager.shared

    @State private var showingSettings = false
    @State private var showingCustomDuration = false
    @State private var customMinutes: String = "45"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status Header
            statusHeader

            Divider()

            // Quick Actions
            quickActions

            Divider()

            // Schedule Info
            scheduleInfo

            Divider()

            // Bottom Actions
            bottomActions
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(statusText)
                        .font(.headline)

                    // Trial badge
                    if !licenseManager.isLicensed {
                        if case .trial(let days) = licenseManager.licenseState {
                            Text("Trial: \(days)d")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }

                Text(statusSubtext)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var statusColor: Color {
        // Always check actual blocking state first
        if blockingService.isBlocking {
            return .red
        } else if scheduleManager.sessionEndTime != nil {
            // Session requested but blocking not yet active
            return .orange
        }
        return .green
    }

    private var statusText: String {
        if blockingService.isBlocking {
            if scheduleManager.sessionEndTime != nil {
                return "Focus Session Active"
            }
            return "Blocking Active"
        } else if scheduleManager.sessionEndTime != nil {
            return "Starting..."
        }
        return "Blocking Inactive"
    }

    private var statusSubtext: String {
        if blockingService.isBlocking {
            if !scheduleManager.remainingTime.isEmpty {
                return "\(scheduleManager.remainingTime) remaining"
            } else if let endTime = configManager.configuration.schedule.nextDeactivation() {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                return "Ends at \(formatter.string(from: endTime))"
            }
            return "Active now"
        } else if scheduleManager.sessionEndTime != nil {
            return "Waiting for activation..."
        }
        return scheduleManager.nextScheduledEvent
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 6) {
            // Show focus session status if there's an active session (even if blocking not fully active yet)
            if scheduleManager.sessionEndTime != nil || blockingService.isBlocking {
                // When blocking is active or focus session is starting, show countdown timer
                HStack {
                    Image(systemName: blockingService.isBlocking ? "lock.fill" : "hourglass")
                        .foregroundColor(blockingService.isBlocking ? .red : .orange)
                    if !scheduleManager.remainingTime.isEmpty {
                        // Focus session with countdown
                        Text("\(scheduleManager.remainingTime) remaining")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.medium)
                    } else if blockingService.isBlocking {
                        // Scheduled blocking or orphaned blocking
                        Text("Blocking until \(scheduleEndTime)")
                            .font(.subheadline)
                    } else {
                        // Focus session starting
                        Text("Starting focus session...")
                            .font(.subheadline)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                Text(blockingService.isBlocking ? "Stay focused! Blocking will end automatically." : "Enter your password to start blocking.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button(action: {
                    scheduleManager.forceActivate()
                }) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("Start Blocking Now")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                // Focus session options
                if showingCustomDuration {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Duration:")
                                .font(.subheadline)
                            TextField("min", text: $customMinutes)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("minutes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let maxMinutes = minutesUntilNextSchedule {
                            Text("Max \(maxMinutes) min (schedule starts soon)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }

                        HStack(spacing: 8) {
                            Button("Cancel") {
                                showingCustomDuration = false
                            }
                            .buttonStyle(.bordered)

                            Button("Start") {
                                if let minutes = Int(customMinutes), minutes > 0 {
                                    // Cap to max available time (minimum 1 minute)
                                    var cappedMinutes = minutes
                                    if let maxMinutes = minutesUntilNextSchedule {
                                        cappedMinutes = min(minutes, max(1, maxMinutes))
                                    }
                                    if cappedMinutes > 0 {
                                        scheduleManager.blockForDuration(minutes: cappedMinutes)
                                    }
                                    showingCustomDuration = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(Int(customMinutes) ?? 0 <= 0)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Menu {
                        ForEach(availableDurations, id: \.minutes) { option in
                            Button(option.label) {
                                scheduleManager.blockForDuration(minutes: option.minutes)
                            }
                        }

                        if availableDurations.isEmpty {
                            Text("Schedule starts soon")
                                .foregroundColor(.secondary)
                        }

                        if !availableDurations.isEmpty {
                            Divider()
                            Button("Custom duration...") {
                                showingCustomDuration = true
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "timer")
                            Text("Focus Session...")
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var scheduleEndTime: String {
        let schedule = configManager.configuration.schedule
        return schedule.currentDayEndTime() ?? "scheduled end"
    }

    // Check if currently in a scheduled blocking period (not a focus session)
    private var isScheduledBlocking: Bool {
        blockingService.isBlocking && scheduleManager.remainingTime.isEmpty
    }

    // Calculate minutes until next scheduled start (for capping focus sessions)
    private var minutesUntilNextSchedule: Int? {
        guard configManager.configuration.enabled else { return nil }

        let schedule = configManager.configuration.schedule
        guard let nextStart = schedule.nextActivation() else { return nil }

        let minutes = Int(nextStart.timeIntervalSinceNow / 60)
        return minutes > 0 ? minutes : nil
    }

    // Get available duration options based on time until next schedule
    private var availableDurations: [(label: String, minutes: Int)] {
        let allOptions: [(label: String, minutes: Int)] = [
            ("15 minutes", 15),
            ("30 minutes", 30),
            ("45 minutes", 45),
            ("1 hour", 60),
            ("2 hours", 120)
        ]

        guard let maxMinutes = minutesUntilNextSchedule else {
            return allOptions
        }

        // Filter to only show options that fit before next schedule
        return allOptions.filter { $0.minutes <= maxMinutes }
    }

    // MARK: - Schedule Info

    private var scheduleInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Schedule")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Toggle("", isOn: $configManager.configuration.enabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
            }

            if configManager.configuration.enabled {
                Text(configManager.configuration.schedule.summaryDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: 6) {
            Button(action: {
                showingSettings = true
                NSApp.activate(ignoringOtherApps: true)
                SettingsWindowController.shared.showWindow()
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit NotToday 2")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
}
