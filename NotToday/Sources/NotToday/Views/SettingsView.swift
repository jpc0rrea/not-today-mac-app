import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager = ConfigurationManager.shared
    @ObservedObject var licenseManager = LicenseManager.shared
    @State private var newSite: String = ""
    @State private var selectedTab: SettingsTab = .sites
    @State private var showActivationSheet = false
    @State private var showLicenseManagement = false

    enum SettingsTab: String, CaseIterable {
        case sites = "Blocked Sites"
        case schedule = "Schedule"
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

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

            Text("Set different hours for each day")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(DayOfWeek.allCases) { day in
                DayScheduleRow(
                    day: day,
                    schedule: configManager.configuration.schedule.scheduleFor(day: day),
                    onToggle: {
                        configManager.toggleDay(day)
                    },
                    onUpdateTime: { startHour, startMinute, endHour, endMinute in
                        configManager.updateDayTime(
                            day: day,
                            startHour: startHour,
                            startMinute: startMinute,
                            endHour: endHour,
                            endMinute: endMinute
                        )
                    }
                )
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "hand.raised.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("NotToday")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Version 1.0.0")
                    .foregroundColor(.secondary)

                Text("Block distractions. Not today.")
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

                    Button("Open in Finder") {
                        let url = URL(fileURLWithPath: configManager.configFilePath)
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                    .buttonStyle(.bordered)
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

// MARK: - Day Schedule Row

struct DayScheduleRow: View {
    let day: DayOfWeek
    let schedule: DaySchedule
    let onToggle: () -> Void
    let onUpdateTime: (Int?, Int?, Int?, Int?) -> Void

    var body: some View {
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
                // Start time
                HStack(spacing: 2) {
                    Picker("", selection: Binding(
                        get: { schedule.startHour },
                        set: { onUpdateTime($0, nil, nil, nil) }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)

                    Text(":")

                    Picker("", selection: Binding(
                        get: { schedule.startMinute },
                        set: { onUpdateTime(nil, $0, nil, nil) }
                    )) {
                        ForEach([0, 15, 30, 45], id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }

                Text("to")
                    .foregroundColor(.secondary)

                // End time
                HStack(spacing: 2) {
                    Picker("", selection: Binding(
                        get: { schedule.endHour },
                        set: { onUpdateTime(nil, nil, $0, nil) }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)

                    Text(":")

                    Picker("", selection: Binding(
                        get: { schedule.endMinute },
                        set: { onUpdateTime(nil, nil, nil, $0) }
                    )) {
                        ForEach([0, 15, 30, 45], id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }
            } else {
                Text("Disabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
        window?.title = "NotToday Settings"
        window?.styleMask = [.titled, .closable, .miniaturizable]
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
