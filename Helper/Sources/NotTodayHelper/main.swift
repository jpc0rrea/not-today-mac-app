import Foundation

// MARK: - Helper Entry Point

/// The privileged helper daemon that runs as root
/// This daemon handles blocking operations without requiring user password each time

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate

// Start the run loop
listener.resume()
RunLoop.main.run()
