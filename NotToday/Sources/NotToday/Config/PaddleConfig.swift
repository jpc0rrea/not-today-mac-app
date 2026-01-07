import Foundation

/// Paddle SDK Configuration
/// Fill in these values from your Paddle dashboard after setting up your product
enum PaddleConfig {
    // MARK: - Paddle Credentials
    // Get these from: https://vendors.paddle.com/sdk-products

    /// Your Paddle Vendor ID
    static let vendorID = "YOUR_VENDOR_ID"

    /// Your Paddle Product ID for NotToday
    static let productID = "YOUR_PRODUCT_ID"

    /// Your Paddle API Key
    static let apiKey = "YOUR_API_KEY"

    // MARK: - Product Configuration

    /// Trial length in days (0 to disable trial)
    static let trialDays = 14

    /// Maximum activations per license
    static let maxActivations = 3

    /// Product name shown in Paddle dialogs
    static let productName = "NotToday"

    /// Vendor/Company name shown in Paddle dialogs
    static let vendorName = "Your Company Name"

    // MARK: - Validation

    /// Check if credentials are configured
    static var isConfigured: Bool {
        return vendorID != "YOUR_VENDOR_ID" &&
               productID != "YOUR_PRODUCT_ID" &&
               apiKey != "YOUR_API_KEY"
    }
}
