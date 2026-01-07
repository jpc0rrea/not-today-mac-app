import Foundation
import AppKit
import Security

class BlockingService: ObservableObject {
    static let shared = BlockingService()

    @Published var status: BlockingStatus = .inactive
    @Published var isBlocking: Bool = false

    private let hostsPath = "/etc/hosts"
    private let blockMarkerStart = "# NotToday START - DO NOT EDIT THIS SECTION"
    private let blockMarkerEnd = "# NotToday END"

    // Store authorization reference to reuse within a session
    private var authRef: AuthorizationRef?

    // Track if activation is in progress to prevent duplicate password prompts
    private var isActivationInProgress: Bool = false

    private var helperScriptPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NotToday/focus-helper.sh")
    }

    private var deactivateScriptPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NotToday/deactivate.sh")
    }

    private let launchDaemonPath = "/Library/LaunchDaemons/com.nottoday.deactivate.plist"
    private let deactivateScriptSystemPath = "/Library/Application Support/NotToday/deactivate-scheduled.sh"

    init() {
        checkCurrentStatus()
        setupHelperScript()
        setupDeactivateScript()
    }

    // MARK: - Status Check

    func checkCurrentStatus() {
        guard let hostsContent = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            status = .error("Cannot read hosts file")
            return
        }

        isBlocking = hostsContent.contains(blockMarkerStart)
        status = isBlocking ? .active : .inactive
    }

    // MARK: - Blocking Operations

    func activateBlocking(sites: [String]) {
        // Prevent multiple simultaneous activations
        guard !isActivationInProgress else {
            print("Activation already in progress, skipping")
            return
        }

        isActivationInProgress = true

        let blockEntries = sites.map { "127.0.0.1 \($0)" }.joined(separator: "\n")
        let blockContent = """

        \(blockMarkerStart)
        \(blockEntries)
        \(blockMarkerEnd)
        """

        let script = """
        #!/bin/bash
        # Remove existing NotToday entries first
        sed -i '' '/# NotToday START/,/# NotToday END/d' /etc/hosts
        # Add new entries
        echo '\(blockContent)' | tee -a /etc/hosts > /dev/null
        # Flush DNS cache
        dscacheutil -flushcache
        killall -HUP mDNSResponder 2>/dev/null || true
        sleep 1
        echo "Blocking activated"
        """

        executeWithAdmin(script: script) { [weak self] success in
            DispatchQueue.main.async {
                self?.isActivationInProgress = false
                if success {
                    self?.isBlocking = true
                    self?.status = .active
                } else {
                    self?.status = .error("Failed to activate blocking")
                }
            }
        }
    }

    func deactivateBlocking() {
        let script = """
        #!/bin/bash
        # Remove NotToday entries
        sed -i '' '/# NotToday START/,/# NotToday END/d' /etc/hosts
        # Flush DNS cache
        dscacheutil -flushcache
        killall -HUP mDNSResponder 2>/dev/null || true
        sleep 1
        echo "Blocking deactivated"
        """

        executeWithAdmin(script: script) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.isBlocking = false
                    self?.status = .inactive
                } else {
                    self?.status = .error("Failed to deactivate blocking")
                }
            }
        }
    }

    /// Activate blocking with a scheduled deactivation - only prompts for password/TouchID ONCE
    func activateBlockingWithScheduledEnd(sites: [String], minutes: Int, completion: @escaping (Bool) -> Void) {
        // Prevent multiple simultaneous activations
        guard !isActivationInProgress else {
            print("Activation already in progress, skipping")
            completion(false)
            return
        }

        // If already blocking, just update status and return success
        checkCurrentStatus()
        if isBlocking {
            print("Already blocking, skipping activation")
            completion(true)
            return
        }

        guard minutes > 0 else {
            completion(false)
            return
        }

        isActivationInProgress = true

        // Calculate end time - timer starts when user confirms authentication
        let endTime = Date().addingTimeInterval(Double(minutes * 60))

        let blockEntries = sites.map { "127.0.0.1 \($0)" }.joined(separator: "\n")
        let blockContent = """

        \(blockMarkerStart)
        \(blockEntries)
        \(blockMarkerEnd)
        """

        // Calculate the end time components for launchd
        let calendar = Calendar.current
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: endTime)

        // Create the deactivation script that will run at the scheduled time
        let deactivateScript = """
        #!/bin/bash
        # NotToday Scheduled Deactivation Script
        # Auto-generated - will run once and clean up

        # Remove NotToday entries from hosts
        sed -i '' '/# NotToday START/,/# NotToday END/d' /etc/hosts

        # Flush DNS cache
        dscacheutil -flushcache
        killall -HUP mDNSResponder 2>/dev/null || true

        # Clean up: remove the LaunchDaemon and this script
        launchctl unload /Library/LaunchDaemons/com.nottoday.deactivate.plist 2>/dev/null || true
        rm -f /Library/LaunchDaemons/com.nottoday.deactivate.plist
        rm -f "/Library/Application Support/NotToday/deactivate-scheduled.sh"

        echo "NotToday: Blocking deactivated at $(date)"
        """

        // Create the LaunchDaemon plist that will trigger at the end time
        let launchDaemonPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.nottoday.deactivate</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>/Library/Application Support/NotToday/deactivate-scheduled.sh</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Month</key>
                <integer>\(endComponents.month ?? 1)</integer>
                <key>Day</key>
                <integer>\(endComponents.day ?? 1)</integer>
                <key>Hour</key>
                <integer>\(endComponents.hour ?? 0)</integer>
                <key>Minute</key>
                <integer>\(endComponents.minute ?? 0)</integer>
            </dict>
            <key>RunAtLoad</key>
            <false/>
        </dict>
        </plist>
        """

        // Create a script that:
        // 1. Activates blocking now
        // 2. Sets up LaunchDaemon for automatic deactivation
        let script = """
        #!/bin/bash

        # Remove existing NotToday entries first
        sed -i '' '/# NotToday START/,/# NotToday END/d' /etc/hosts

        # Add new entries
        echo '\(blockContent)' | tee -a /etc/hosts > /dev/null

        # Flush DNS cache
        dscacheutil -flushcache
        killall -HUP mDNSResponder 2>/dev/null || true

        # Create directory for deactivation script
        mkdir -p "/Library/Application Support/NotToday"

        # Write deactivation script
        cat > "/Library/Application Support/NotToday/deactivate-scheduled.sh" << 'DEACTIVATE_SCRIPT'
        \(deactivateScript)
        DEACTIVATE_SCRIPT
        chmod +x "/Library/Application Support/NotToday/deactivate-scheduled.sh"

        # Remove any existing LaunchDaemon
        launchctl unload /Library/LaunchDaemons/com.nottoday.deactivate.plist 2>/dev/null || true

        # Write LaunchDaemon plist
        cat > /Library/LaunchDaemons/com.nottoday.deactivate.plist << 'PLIST_END'
        \(launchDaemonPlist)
        PLIST_END

        # Set proper permissions
        chmod 644 /Library/LaunchDaemons/com.nottoday.deactivate.plist
        chown root:wheel /Library/LaunchDaemons/com.nottoday.deactivate.plist

        # Load the LaunchDaemon
        launchctl load /Library/LaunchDaemons/com.nottoday.deactivate.plist

        # Verify blocking was applied
        if grep -q "NotToday START" /etc/hosts; then
            echo "Blocking verified - will auto-deactivate at \(endComponents.hour ?? 0):\(String(format: "%02d", endComponents.minute ?? 0))"
        else
            echo "ERROR: Blocking not applied"
            exit 1
        fi
        """

        executeWithAdmin(script: script) { [weak self] success in
            DispatchQueue.main.async {
                self?.isActivationInProgress = false
                if success {
                    self?.isBlocking = true
                    self?.status = .active
                    completion(true)
                } else {
                    self?.status = .error("Failed to activate blocking")
                    completion(false)
                }
            }
        }
    }

    /// Silently deactivate blocking (for when scheduled deactivation already ran)
    func syncBlockingStatus() {
        checkCurrentStatus()
    }

    // MARK: - AppleScript Admin Execution

    private func executeWithAdmin(script: String, completion: @escaping (Bool) -> Void) {
        // Write script to temp file
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("focus-block-\(UUID().uuidString).sh")

        do {
            try script.write(to: tempScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        } catch {
            print("Failed to write temp script: \(error)")
            completion(false)
            return
        }

        // Execute with admin privileges using AppleScript
        // TouchID support depends on system settings (System Settings > Touch ID & Password > Use Touch ID for sudo)
        let appleScript = """
        do shell script "\(tempScript.path)" with administrator privileges with prompt "NotToday needs to modify system settings to block distracting websites."
        """

        guard let scriptObject = NSAppleScript(source: appleScript) else {
            print("Failed to create AppleScript")
            try? FileManager.default.removeItem(at: tempScript)
            completion(false)
            return
        }

        // Run on background thread to not block UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            let result = scriptObject.executeAndReturnError(&error)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempScript)

            let success = error == nil
            if let error = error {
                print("AppleScript error: \(error)")
            } else {
                print("AppleScript succeeded: \(result.stringValue ?? "no output")")
            }

            DispatchQueue.main.async {
                // Force update the blocking status from hosts file
                self?.checkCurrentStatus()
                completion(success)
            }
        }
    }

    // MARK: - Helper Script Setup

    private func setupHelperScript() {
        let script = """
        #!/bin/bash
        # NotToday Helper Script
        # This script can be used to manually control blocking from the command line

        HOSTS_FILE="/etc/hosts"
        MARKER_START="# NotToday START - DO NOT EDIT THIS SECTION"
        MARKER_END="# NotToday END"

        case "$1" in
            status)
                if grep -q "$MARKER_START" "$HOSTS_FILE"; then
                    echo "Blocking is ACTIVE"
                    exit 0
                else
                    echo "Blocking is INACTIVE"
                    exit 1
                fi
                ;;
            activate)
                CONFIG_FILE="$HOME/Library/Application Support/NotToday/config.json"
                if [ ! -f "$CONFIG_FILE" ]; then
                    echo "Config file not found"
                    exit 1
                fi

                # Remove existing entries
                sudo sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

                # Add new entries
                echo "" | sudo tee -a "$HOSTS_FILE" > /dev/null
                echo "$MARKER_START" | sudo tee -a "$HOSTS_FILE" > /dev/null

                # Parse blocked sites from config
                python3 -c "import json; config = json.load(open('$CONFIG_FILE')); print('\\n'.join(['127.0.0.1 ' + site for site in config['blockedSites']]))" | sudo tee -a "$HOSTS_FILE" > /dev/null

                echo "$MARKER_END" | sudo tee -a "$HOSTS_FILE" > /dev/null

                # Flush DNS
                sudo dscacheutil -flushcache
                sudo killall -HUP mDNSResponder 2>/dev/null

                echo "Blocking ACTIVATED"
                ;;
            deactivate)
                sudo sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"
                sudo dscacheutil -flushcache
                sudo killall -HUP mDNSResponder 2>/dev/null
                echo "Blocking DEACTIVATED"
                ;;
            *)
                echo "Usage: $0 {status|activate|deactivate}"
                exit 1
                ;;
        esac
        """

        let folder = helperScriptPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? script.write(to: helperScriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScriptPath.path)
    }

    private func setupDeactivateScript() {
        let script = """
        #!/bin/bash
        # NotToday Deactivate Script
        HOSTS_FILE="/etc/hosts"
        MARKER_START="# NotToday START"
        MARKER_END="# NotToday END"

        # Remove NotToday entries
        sudo sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

        # Flush DNS
        sudo dscacheutil -flushcache
        sudo killall -HUP mDNSResponder 2>/dev/null

        echo "Blocking DEACTIVATED"
        """

        let folder = deactivateScriptPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? script.write(to: deactivateScriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deactivateScriptPath.path)
    }

    // MARK: - Get Blocked Sites

    func getBlockedSitesFromHosts() -> [String] {
        guard let hostsContent = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return []
        }

        var sites: [String] = []
        var inBlockSection = false

        for line in hostsContent.components(separatedBy: .newlines) {
            if line.contains(blockMarkerStart) {
                inBlockSection = true
                continue
            }
            if line.contains(blockMarkerEnd) {
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
}
