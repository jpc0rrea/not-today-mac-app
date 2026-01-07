import SwiftUI
import AppKit
import ServiceManagement

@main
struct NotTodayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var countdownTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Enable launch at login automatically
        enableLaunchAtLogin()

        // Initialize services
        _ = ConfigurationManager.shared
        _ = BlockingService.shared
        _ = ScheduleManager.shared

        // Setup menu bar
        setupMenuBar()

        // Check initial blocking state
        BlockingService.shared.checkCurrentStatus()
        ScheduleManager.shared.checkAndUpdateBlocking()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateStatusIcon()

            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 350)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())

        // Subscribe to blocking status changes to update icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusIcon),
            name: NSNotification.Name("BlockingStatusChanged"),
            object: nil
        )

        // Update icon periodically
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }

        // Start countdown timer for menu bar updates
        startMenuBarCountdown()
    }

    private func startMenuBarCountdown() {
        // Create timer and add to run loop with .common mode to ensure updates during menu interactions
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer

        // Also update immediately
        updateMenuBarTitle()
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }

        let scheduleManager = ScheduleManager.shared

        if !scheduleManager.remainingTime.isEmpty {
            // Show countdown in menu bar
            button.title = " \(scheduleManager.remainingTime)"
        } else {
            // Clear title when not in focus session
            button.title = ""
        }
    }

    @objc private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        // Load custom menu bar icon from bundle resources
        // In SwiftPM, resources are in Bundle.module
        if let iconURL = Bundle.module.url(forResource: "menubar_icon_22x22", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            image.isTemplate = true  // Makes it adapt to light/dark mode
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            // Fallback to system symbol if custom icon not found
            let isBlocking = BlockingService.shared.isBlocking
            if isBlocking {
                button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Blocking Active")
            } else {
                button.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "Blocking Inactive")
            }
            button.image?.isTemplate = true
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Ensure popover gets focus
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Optionally deactivate blocking when app quits
        // Uncomment if you want blocking to stop when app closes:
        // BlockingService.shared.deactivateBlocking()
    }
}

// MARK: - Launch at Login Helper

extension AppDelegate {
    func enableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                // Check if already enabled
                let service = SMAppService.mainApp
                if service.status != .enabled {
                    try service.register()
                    print("NotToday registered to launch at login")
                }
            } catch {
                print("Failed to register launch at login: \(error)")
            }
        }
    }

    func disableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("NotToday unregistered from launch at login")
            } catch {
                print("Failed to unregister launch at login: \(error)")
            }
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
