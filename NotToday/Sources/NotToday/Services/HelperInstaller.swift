import Foundation
import ServiceManagement
import Security

/// Manages installation and status of the privileged helper
class HelperInstaller: ObservableObject {
    static let shared = HelperInstaller()

    @Published var isHelperInstalled: Bool = false
    @Published var installationError: String?
    @Published var isInstalling: Bool = false

    private init() {
        checkHelperStatus()
    }

    // MARK: - Status Check

    /// Check if the helper is installed and running
    func checkHelperStatus() {
        // First check if the helper binary exists
        let helperExists = FileManager.default.fileExists(atPath: HelperConstants.helperInstallPath)

        if helperExists {
            // Try to communicate with the helper to verify it's working
            HelperConnection.shared.checkHelperStatus { [weak self] success, error in
                DispatchQueue.main.async {
                    self?.isHelperInstalled = success
                    if !success {
                        self?.installationError = error
                    }
                }
            }
        } else {
            isHelperInstalled = false
        }
    }

    // MARK: - Installation

    /// Install the privileged helper using SMAppService (macOS 13+)
    @available(macOS 13.0, *)
    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        guard !isInstalling else {
            completion(false, "Installation already in progress")
            return
        }

        isInstalling = true
        installationError = nil

        // Use legacy installation with authorization for privileged helper
        installHelperWithAuthorization { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isInstalling = false
                self?.installationError = error
                if success {
                    self?.isHelperInstalled = true
                }
                completion(success, error)
            }
        }
    }

    /// Install helper using Authorization Services (traditional approach)
    private func installHelperWithAuthorization(completion: @escaping (Bool, String?) -> Void) {
        // Get the path to the helper inside our app bundle
        guard let helperSourcePath = getHelperSourcePath() else {
            completion(false, "Helper not found in app bundle")
            return
        }

        // Create the installation script
        let installScript = createInstallScript(helperPath: helperSourcePath)

        // Execute with admin privileges
        executeWithAdminPrivileges(script: installScript, completion: completion)
    }

    private func getHelperSourcePath() -> String? {
        // The helper should be in our app bundle
        let bundle = Bundle.main
        if let helperPath = bundle.path(forResource: "com.nottoday.helper", ofType: nil) {
            return helperPath
        }

        // Try auxiliary executables path
        if let auxPath = bundle.path(forAuxiliaryExecutable: "com.nottoday.helper") {
            return auxPath
        }

        // For development, check if helper is built alongside the app
        let executablePath = bundle.executablePath ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let devHelperPath = (executableDir as NSString).appendingPathComponent("com.nottoday.helper")
        if FileManager.default.fileExists(atPath: devHelperPath) {
            return devHelperPath
        }

        return nil
    }

    private func createInstallScript(helperPath: String) -> String {
        let launchdPlist = createLaunchdPlist()

        return """
        #!/bin/bash
        set -e

        # Create directories
        mkdir -p /Library/PrivilegedHelperTools
        mkdir -p "/Library/Application Support/NotToday"

        # Stop existing helper if running
        launchctl bootout system/\(HelperConstants.helperBundleIdentifier) 2>/dev/null || true

        # Copy helper binary
        cp "\(helperPath)" "\(HelperConstants.helperInstallPath)"
        chmod 544 "\(HelperConstants.helperInstallPath)"
        chown root:wheel "\(HelperConstants.helperInstallPath)"

        # Write launchd plist
        cat > "\(HelperConstants.launchdPlistPath)" << 'PLIST_EOF'
        \(launchdPlist)
        PLIST_EOF

        chmod 644 "\(HelperConstants.launchdPlistPath)"
        chown root:wheel "\(HelperConstants.launchdPlistPath)"

        # Load the helper
        launchctl bootstrap system "\(HelperConstants.launchdPlistPath)"

        echo "Helper installed successfully"
        """
    }

    private func createLaunchdPlist() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(HelperConstants.helperBundleIdentifier)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(HelperConstants.helperInstallPath)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(HelperConstants.machServiceName)</key>
                <true/>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/var/log/nottoday-helper.log</string>
            <key>StandardOutPath</key>
            <string>/var/log/nottoday-helper.log</string>
        </dict>
        </plist>
        """
    }

    private func executeWithAdminPrivileges(script: String, completion: @escaping (Bool, String?) -> Void) {
        // Write script to temp file
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("nottoday-install-\(UUID().uuidString).sh")

        do {
            try script.write(to: tempScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        } catch {
            completion(false, "Failed to write installation script: \(error)")
            return
        }

        // Execute with admin privileges using AppleScript
        let appleScript = """
        do shell script "\(tempScript.path)" with administrator privileges with prompt "NotToday 2 needs to install a helper to enable scheduled blocking without password prompts."
        """

        guard let scriptObject = NSAppleScript(source: appleScript) else {
            try? FileManager.default.removeItem(at: tempScript)
            completion(false, "Failed to create AppleScript")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let result = scriptObject.executeAndReturnError(&error)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempScript)

            let success = error == nil
            let errorMessage = error?[NSAppleScript.errorMessage] as? String

            DispatchQueue.main.async {
                if success {
                    print("Helper installation succeeded: \(result.stringValue ?? "no output")")
                    completion(true, nil)
                } else {
                    print("Helper installation failed: \(errorMessage ?? "unknown error")")
                    completion(false, errorMessage)
                }
            }
        }
    }

    // MARK: - Uninstallation

    /// Uninstall the privileged helper
    func uninstallHelper(completion: @escaping (Bool, String?) -> Void) {
        let uninstallScript = """
        #!/bin/bash

        # Stop the helper
        launchctl bootout system/\(HelperConstants.helperBundleIdentifier) 2>/dev/null || true

        # Remove files
        rm -f "\(HelperConstants.helperInstallPath)"
        rm -f "\(HelperConstants.launchdPlistPath)"
        rm -f "\(HelperConstants.helperConfigPath)"

        echo "Helper uninstalled successfully"
        """

        executeWithAdminPrivileges(script: uninstallScript) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isHelperInstalled = false
                    HelperConnection.shared.invalidateConnection()
                }
                completion(success, error)
            }
        }
    }
}
