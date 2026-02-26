import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager = ConfigurationManager.shared
    @ObservedObject var licenseManager = LicenseManager.shared
    @ObservedObject var helperInstaller = HelperInstaller.shared
    @State private var newSite: String = ""
    @State private var selectedTab: SettingsTab = .sites
    @State private var showActivationSheet = false
    @State private var showLicenseManagement = false
    @State private var showHelperInstallError = false
    @State private var helperInstallErrorMessage = ""

    enum SettingsTab: String, CaseIterable {
        case sites = "Blocked Sites"
        case schedule = "Schedule"
        case helper = "Helper"
        case about = "About"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            blockedSitesTab
                .tabItem {
                    Label("Sites", systemImage: "globe")
                }
                .tag(SettingsTab.sites)

            scheduleTab
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(SettingsTab.schedule)

            helperTab
                .tabItem {
                    Label("Helper", systemImage: "gearshape.2")
                }
                .tag(SettingsTab.helper)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 520, height: 500)
        .padding()
    }

    // MARK: - Blocked Sites Tab

    private var blockedSitesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Blocked Sites")
                .font(.title2)
                .fontWeight(.semibold)

            Text("These websites will be blocked during scheduled focus time.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Add new site
            HStack {
                TextField("Enter website (e.g., twitter.com)", text: $newSite)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addSite()
                    }

                Button("Add") {
                    addSite()
                }
                .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Sites list
            List {
                ForEach(configManager.configuration.blockedSites, id: \.self) { site in
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.secondary)
                        Text(site)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                    }
                }
                .onDelete { offsets in
                    configManager.removeSites(at: offsets)
                }
            }
            .listStyle(.bordered)

            HStack {
                Text("\(configManager.configuration.blockedSites.count) sites blocked")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Reset to Defaults") {
                    configManager.resetToDefaults()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func addSite() {
        let site = newSite.trimmingCharacters(in: .whitespaces)
        guard !site.isEmpty else { return }
        configManager.addSite(site)
        newSite = ""
    }

    // MARK: - Schedule Tab

    @State private var scheduleSaved = false
    @ObservedObject var blockingService = BlockingService.shared
    @State private var showActiveSessionWarning = false

    private var scheduleTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Schedule")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Configure when blocking should automatically activate.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Toggle("Enable automatic scheduling", isOn: $configManager.configuration.enabled)
                    .toggleStyle(.switch)

                if configManager.configuration.enabled {
                    // Quick presets
                    quickPresetsSection
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                    // Per-day schedules
                    perDayScheduleSection
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                Spacer()

                // Validation error
                if let error = configManager.scheduleValidationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }

                // Save button
                HStack {
                    Spacer()

                    if scheduleSaved {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Saved!")
                                .foregroundColor(.green)
                        }
                        .transition(.opacity)
                    }

                    Button(action: {
                        if blockingService.isBlocking {
                            showActiveSessionWarning = true
                        } else {
                            saveSchedule()
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save Schedule")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!configManager.isScheduleValid)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .alert("Blocking Session Active", isPresented: $showActiveSessionWarning) {
            Button("OK") {
                saveSchedule()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A blocking session is currently active. Your changes will take effect after the current session ends.")
        }
    }

    private func saveSchedule() {
        // Save configuration locally
        configManager.saveConfiguration()

        // Only sync to helper if NOT currently blocking
        // If blocking is active, changes will be synced when the session ends
        if !blockingService.isBlocking {
            BlockingService.shared.syncScheduleToHelper(configuration: configManager.configuration)
        } else {
            // Mark that we have pending changes to sync
            ScheduleManager.shared.hasPendingScheduleChanges = true
        }

        // Show saved feedback
        withAnimation {
            scheduleSaved = true
        }

        // Hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                scheduleSaved = false
            }
        }
    }

    private var quickPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Presets")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Weekdays") {
                    configManager.applyWeekdaysPreset()
                }
                .buttonStyle(.bordered)

                Button("Weekends") {
                    configManager.applyWeekendsPreset()
                }
                .buttonStyle(.bordered)

                Button("Every Day") {
                    configManager.applyEveryDayPreset()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var perDayScheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Day Schedule")
                .font(.headline)

            Text("Set different hours for each day. Add multiple time ranges per day.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(DayOfWeek.allCases) { day in
                DayScheduleSection(
                    day: day,
                    schedule: configManager.configuration.schedule.scheduleFor(day: day),
                    onToggle: {
                        configManager.toggleDay(day)
                    },
                    onUpdateRange: { index, range in
                        configManager.updateTimeRange(day: day, rangeIndex: index, range: range)
                    },
                    onAddRange: {
                        configManager.addTimeRange(day: day)
                    },
                    onRemoveRange: { index in
                        configManager.removeTimeRange(day: day, rangeIndex: index)
                    }
                )
            }
        }
    }

    // MARK: - Helper Tab

    private var helperTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privileged Helper")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Install a helper to enable scheduled blocking without password prompts.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Status section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(helperInstaller.isHelperInstalled ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)

                    Text(helperInstaller.isHelperInstalled ? "Helper Installed" : "Helper Not Installed")
                        .fontWeight(.medium)
                }

                if helperInstaller.isHelperInstalled {
                    Text("Scheduled blocking will activate automatically without requiring your password each time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Without the helper, you'll need to enter your password each time blocking activates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Benefits section
            VStack(alignment: .leading, spacing: 8) {
                Text("Benefits of Installing the Helper:")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    benefitRow(icon: "checkmark.circle.fill", text: "No password prompts for scheduled blocking")
                    benefitRow(icon: "checkmark.circle.fill", text: "Blocking works even if the app is closed")
                    benefitRow(icon: "checkmark.circle.fill", text: "Seamless focus session starts")
                    benefitRow(icon: "checkmark.circle.fill", text: "One-time installation with admin password")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            Spacer()

            // Action buttons
            HStack {
                if helperInstaller.isHelperInstalled {
                    Button("Uninstall Helper") {
                        uninstallHelper()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                } else {
                    Button(action: installHelper) {
                        if helperInstaller.isInstalling {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.horizontal, 8)
                        } else {
                            Text("Install Helper")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(helperInstaller.isInstalling)
                }

                Spacer()

                Button("Refresh Status") {
                    helperInstaller.checkHelperStatus()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Installation Error", isPresented: $showHelperInstallError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(helperInstallErrorMessage)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
    }

    private func installHelper() {
        if #available(macOS 13.0, *) {
            helperInstaller.installHelper { success, error in
                if !success {
                    helperInstallErrorMessage = error ?? "Unknown error occurred"
                    showHelperInstallError = true
                } else {
                    // Sync schedule after successful installation
                    BlockingService.shared.syncScheduleToHelper(configuration: configManager.configuration)
                }
            }
        }
    }

    private func uninstallHelper() {
        helperInstaller.uninstallHelper { success, error in
            if !success {
                helperInstallErrorMessage = error ?? "Unknown error occurred"
                showHelperInstallError = true
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 80, height: 80)
                    Text("✋🏾")
                        .font(.system(size: 44))
                }

                Text("NotToday 2")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Version 2.0.0")
                    .foregroundColor(.secondary)

                Text("Block distractions. Not today. No passwords.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // License Status Section
                licenseStatusSection

                Divider()
                    .padding(.horizontal, 40)

                VStack(spacing: 8) {
                    Text("Configuration File:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(configManager.configFilePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Button("Open in Finder") {
                            let url = URL(fileURLWithPath: configManager.configFilePath)
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                        .buttonStyle(.bordered)

                        Button("Test Notification") {
                            ScheduleManager.shared.sendSessionStartNotification(minutes: 1)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer(minLength: 20)
            }
        }
        .sheet(isPresented: $showActivationSheet) {
            LicenseActivationView()
        }
        .sheet(isPresented: $showLicenseManagement) {
            LicenseManagementView()
        }
    }

    // MARK: - License Status Section

    @ViewBuilder
    private var licenseStatusSection: some View {
        VStack(spacing: 12) {
            // Status badge
            HStack {
                Circle()
                    .fill(licenseManager.isLicensed ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(licenseManager.licenseState.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Trial info
            if case .trial(let days) = licenseManager.licenseState {
                Text("\(days) days remaining in trial")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Action buttons based on state
            if licenseManager.isLicensed {
                Button("Manage License") {
                    showLicenseManagement = true
                }
                .buttonStyle(.bordered)
            } else {
                VStack(spacing: 8) {
                    Button("Purchase License") {
                        licenseManager.showPurchaseDialog()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Enter License Key") {
                        showActivationSheet = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 40)
    }
}

// MARK: - Day Schedule Section (supports multiple time ranges)

struct DayScheduleSection: View {
    let day: DayOfWeek
    let schedule: DaySchedule
    let onToggle: () -> Void
    let onUpdateRange: (Int, TimeRange) -> Void
    let onAddRange: () -> Void
    let onRemoveRange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: Day toggle + first time range (or "Disabled")
            HStack(spacing: 12) {
                // Day toggle
                Button(action: onToggle) {
                    Text(day.shortName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 40, height: 28)
                        .background(schedule.enabled ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundColor(schedule.enabled ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                if schedule.enabled {
                    if let firstRange = schedule.timeRanges.first {
                        TimeRangeRow(
                            range: firstRange,
                            onUpdate: { updatedRange in
                                onUpdateRange(0, updatedRange)
                            }
                        )

                        // Delete button for first range (only if more than one)
                        if schedule.timeRanges.count > 1 {
                            Button(action: { onRemoveRange(0) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Validation error for first range
            if schedule.enabled, let firstRange = schedule.timeRanges.first, let error = firstRange.validationError {
                HStack {
                    Color.clear.frame(width: 52) // 40 + 12 spacing
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                    Spacer()
                }
            }

            // Additional time ranges (2nd, 3rd, etc.)
            if schedule.enabled && schedule.timeRanges.count > 1 {
                ForEach(Array(schedule.timeRanges.dropFirst().enumerated()), id: \.element.id) { index, range in
                    let actualIndex = index + 1

                    HStack(spacing: 12) {
                        // Spacer to align with day toggle
                        Color.clear.frame(width: 40, height: 28)

                        TimeRangeRow(
                            range: range,
                            onUpdate: { updatedRange in
                                onUpdateRange(actualIndex, updatedRange)
                            }
                        )

                        Button(action: { onRemoveRange(actualIndex) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }

                    // Validation error for this range
                    if let error = range.validationError {
                        HStack {
                            Color.clear.frame(width: 52)
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }

            // Add range button
            if schedule.enabled {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 40, height: 20)
                    Button(action: onAddRange) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text("Add time range")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Time Range Row (single time range picker)

struct TimeRangeRow: View {
    let range: TimeRange
    let onUpdate: (TimeRange) -> Void

    var body: some View {
        HStack(spacing: 2) {
            // Start time
            Picker("", selection: Binding(
                get: { range.startHour },
                set: { hour in
                    var updated = range
                    updated.startHour = hour
                    onUpdate(updated)
                }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 55)

            Text(":")

            Picker("", selection: Binding(
                get: { range.startMinute },
                set: { minute in
                    var updated = range
                    updated.startMinute = minute
                    onUpdate(updated)
                }
            )) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .frame(width: 55)

            Text("-")
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // End time
            Picker("", selection: Binding(
                get: { range.endHour },
                set: { hour in
                    var updated = range
                    updated.endHour = hour
                    onUpdate(updated)
                }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 55)

            Text(":")

            Picker("", selection: Binding(
                get: { range.endMinute },
                set: { minute in
                    var updated = range
                    updated.endMinute = minute
                    onUpdate(updated)
                }
            )) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .frame(width: 55)
        }
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        window = NSWindow(contentViewController: hostingController)
        window?.title = "NotToday 2 Settings"
        window?.styleMask = [.titled, .closable, .miniaturizable]
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
