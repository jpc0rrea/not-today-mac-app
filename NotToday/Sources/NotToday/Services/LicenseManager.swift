import Foundation
import SwiftUI

/// Manages app licensing using Paddle SDK
/// Note: Requires Paddle SDK to be integrated for full functionality
@MainActor
class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // MARK: - Published State

    @Published var licenseState: LicenseState = .unknown
    @Published var trialDaysRemaining: Int = 0
    @Published var isLicensed: Bool = false

    // MARK: - Private Properties

    private let trialStartKey = "NotToday.TrialStartDate"
    private let licenseKeyStorageKey = "NotToday.LicenseKey"
    private let licenseEmailStorageKey = "NotToday.LicenseEmail"

    // MARK: - Initialization

    private init() {
        // Check if Paddle is configured
        if !PaddleConfig.isConfigured {
            print("⚠️ Paddle credentials not configured. Running in development mode.")
            // In development mode, allow full access
            #if DEBUG
            licenseState = .activated
            isLicensed = true
            #else
            startTrialIfNeeded()
            #endif
        } else {
            // Initialize Paddle SDK when credentials are configured
            setupPaddle()
        }
    }

    // MARK: - Paddle Setup

    private func setupPaddle() {
        // TODO: Initialize Paddle SDK when integrated
        // This requires the Paddle.framework to be added to the project

        /*
         Example Paddle SDK initialization:

         let config = PADProductConfiguration()
         config.productName = PaddleConfig.productName
         config.vendorName = PaddleConfig.vendorName
         config.trialLength = NSNumber(value: PaddleConfig.trialDays)
         config.trialType = .timeLimited

         paddle = Paddle.sharedInstance(
             withVendorID: PaddleConfig.vendorID,
             apiKey: PaddleConfig.apiKey,
             productID: PaddleConfig.productID,
             configuration: config,
             delegate: self
         )

         product = PADProduct(
             productID: PaddleConfig.productID,
             productType: .sdkProduct,
             configuration: config
         )
         */

        // For now, start trial mode
        startTrialIfNeeded()
    }

    // MARK: - Trial Management

    private func startTrialIfNeeded() {
        let defaults = UserDefaults.standard

        if let trialStart = defaults.object(forKey: trialStartKey) as? Date {
            // Calculate remaining trial days
            let daysSinceStart = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
            let remaining = max(0, PaddleConfig.trialDays - daysSinceStart)

            trialDaysRemaining = remaining

            if remaining > 0 {
                licenseState = .trial(daysRemaining: remaining)
                isLicensed = false
            } else {
                licenseState = .expired
                isLicensed = false
            }
        } else {
            // Start new trial
            defaults.set(Date(), forKey: trialStartKey)
            trialDaysRemaining = PaddleConfig.trialDays
            licenseState = .trial(daysRemaining: PaddleConfig.trialDays)
            isLicensed = false
            print("✅ Started \(PaddleConfig.trialDays)-day trial")
        }
    }

    // MARK: - License Verification

    /// Verify the current license status
    func verifyLicense() async {
        // TODO: Implement Paddle SDK license verification
        // For now, just check trial status
        startTrialIfNeeded()
    }

    // MARK: - License Activation

    /// Activate the app with a license key
    /// - Parameters:
    ///   - email: The email used for purchase
    ///   - licenseKey: The license key from Paddle
    /// - Returns: Whether activation was successful
    func activate(email: String, licenseKey: String) async -> Bool {
        // TODO: Implement Paddle SDK activation
        // For development, accept any non-empty values

        guard !email.isEmpty, !licenseKey.isEmpty else {
            return false
        }

        // Store credentials
        let defaults = UserDefaults.standard
        defaults.set(email, forKey: licenseEmailStorageKey)
        defaults.set(licenseKey, forKey: licenseKeyStorageKey)

        // Update state
        licenseState = .activated
        isLicensed = true

        print("✅ License activated for: \(email)")
        return true
    }

    // MARK: - License Deactivation

    /// Deactivate the current license (for transferring to another device)
    func deactivate() async -> Bool {
        // TODO: Implement Paddle SDK deactivation

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: licenseKeyStorageKey)
        defaults.removeObject(forKey: licenseEmailStorageKey)

        startTrialIfNeeded()

        print("✅ License deactivated")
        return true
    }

    // MARK: - Purchase Flow

    /// Show the Paddle purchase dialog
    func showPurchaseDialog() {
        // TODO: Implement Paddle SDK purchase flow
        // For now, open the product page in browser

        if let url = URL(string: "https://buy.paddle.com/product/\(PaddleConfig.productID)") {
            NSWorkspace.shared.open(url)
        }

        print("💳 Opening purchase dialog...")
    }

    // MARK: - Stored License Info

    /// Get the stored license email
    var storedEmail: String? {
        UserDefaults.standard.string(forKey: licenseEmailStorageKey)
    }

    /// Check if there's a stored license
    var hasStoredLicense: Bool {
        UserDefaults.standard.string(forKey: licenseKeyStorageKey) != nil
    }

    // MARK: - Development Helpers

    /// Reset trial for testing (development only)
    func resetTrial() {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: trialStartKey)
        UserDefaults.standard.removeObject(forKey: licenseKeyStorageKey)
        UserDefaults.standard.removeObject(forKey: licenseEmailStorageKey)
        startTrialIfNeeded()
        print("🔄 Trial reset")
        #endif
    }
}
