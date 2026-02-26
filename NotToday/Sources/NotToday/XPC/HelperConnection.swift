import Foundation

/// Manages the XPC connection to the privileged helper
class HelperConnection {
    static let shared = HelperConnection()

    private var connection: NSXPCConnection?
    private let connectionLock = NSLock()

    private init() {}

    // MARK: - Connection Management

    /// Get or create a connection to the helper
    private func getConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existingConnection = connection {
            return existingConnection
        }

        let newConnection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)

        newConnection.remoteObjectInterface = NSXPCInterface(with: NotTodayHelperProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.connection = nil
            self?.connectionLock.unlock()
            print("HelperConnection: XPC connection invalidated")
        }

        newConnection.interruptionHandler = {
            print("HelperConnection: XPC connection interrupted")
        }

        newConnection.resume()
        connection = newConnection

        return newConnection
    }

    /// Get the remote helper proxy
    private func getHelper() -> NotTodayHelperProtocol? {
        let conn = getConnection()
        return conn.remoteObjectProxyWithErrorHandler { error in
            print("HelperConnection: Remote object proxy error: \(error)")
        } as? NotTodayHelperProtocol
    }

    /// Invalidate the current connection
    func invalidateConnection() {
        connectionLock.lock()
        connection?.invalidate()
        connection = nil
        connectionLock.unlock()
    }

    // MARK: - Helper Operations

    /// Check if the helper is installed and responsive
    func checkHelperStatus(completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Cannot connect to helper")
            return
        }

        helper.getHelperVersion { version in
            DispatchQueue.main.async {
                if version == HelperConstants.helperVersion {
                    completion(true, nil)
                } else {
                    completion(false, "Helper version mismatch: installed=\(version), expected=\(HelperConstants.helperVersion)")
                }
            }
        }
    }

    /// Activate blocking for the specified sites
    func activateBlocking(sites: [String], completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Cannot connect to helper")
            return
        }

        helper.activateBlocking(sites: sites) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    /// Deactivate blocking
    func deactivateBlocking(completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Cannot connect to helper")
            return
        }

        helper.deactivateBlocking { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    /// Check if blocking is currently active
    func isBlockingActive(completion: @escaping (Bool) -> Void) {
        guard let helper = getHelper() else {
            completion(false)
            return
        }

        helper.isBlockingActive { isActive in
            DispatchQueue.main.async {
                completion(isActive)
            }
        }
    }

    /// Get list of currently blocked sites
    func getBlockedSites(completion: @escaping ([String]) -> Void) {
        guard let helper = getHelper() else {
            completion([])
            return
        }

        helper.getBlockedSites { sites in
            DispatchQueue.main.async {
                completion(sites)
            }
        }
    }

    /// Update the helper's schedule configuration
    func updateSchedule(config: HelperScheduleConfig, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Cannot connect to helper")
            return
        }

        guard let scheduleData = try? JSONEncoder().encode(config) else {
            completion(false, "Failed to encode schedule configuration")
            return
        }

        helper.updateSchedule(scheduleData: scheduleData, sites: config.blockedSites) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    /// Enable or disable schedule-based blocking
    func setScheduleEnabled(_ enabled: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Cannot connect to helper")
            return
        }

        helper.setScheduleEnabled(enabled) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    /// Get the helper version
    func getHelperVersion(completion: @escaping (String?) -> Void) {
        guard let helper = getHelper() else {
            completion(nil)
            return
        }

        helper.getHelperVersion { version in
            DispatchQueue.main.async {
                completion(version)
            }
        }
    }

    /// Uninstall the helper
    func uninstallHelper(completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Cannot connect to helper")
            return
        }

        helper.uninstallHelper { success, error in
            DispatchQueue.main.async {
                self.invalidateConnection()
                completion(success, error)
            }
        }
    }
}
