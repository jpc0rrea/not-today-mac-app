import Foundation

/// Represents the current license state of the app
enum LicenseState: Equatable {
    /// License state is being determined
    case unknown

    /// User is in trial period
    case trial(daysRemaining: Int)

    /// Trial has expired, user needs to purchase
    case expired

    /// User has an active license
    case activated

    /// License was revoked or is invalid
    case invalid

    /// Offline but within grace period
    case offlineGracePeriod(daysRemaining: Int)

    /// Check if user can use the app
    var canUseApp: Bool {
        switch self {
        case .trial, .activated, .offlineGracePeriod:
            return true
        case .unknown, .expired, .invalid:
            return false
        }
    }

    /// Human-readable status message
    var statusMessage: String {
        switch self {
        case .unknown:
            return "Checking license..."
        case .trial(let days):
            return "Trial (\(days) days left)"
        case .expired:
            return "Trial Expired"
        case .activated:
            return "Licensed"
        case .invalid:
            return "License Invalid"
        case .offlineGracePeriod(let days):
            return "Offline (\(days) days)"
        }
    }

    /// Color indicator for UI
    var isLicensed: Bool {
        switch self {
        case .activated:
            return true
        default:
            return false
        }
    }
}
