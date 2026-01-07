import SwiftUI

/// View for activating a license with email and license key
struct LicenseActivationView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var licenseManager = LicenseManager.shared

    @State private var email = ""
    @State private var licenseKey = ""
    @State private var isActivating = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                Text("Activate NotToday")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter your license key received after purchase")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Input fields
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("your@email.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("License Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            // Success message
            if showSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("License activated successfully!")
                        .foregroundColor(.green)
                }
                .font(.subheadline)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button(action: activateLicense) {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || licenseKey.isEmpty || isActivating)
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Purchase link
            VStack(spacing: 8) {
                Text("Don't have a license?")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Purchase NotToday") {
                    licenseManager.showPurchaseDialog()
                }
                .buttonStyle(.link)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func activateLicense() {
        isActivating = true
        errorMessage = nil
        showSuccess = false

        Task {
            let success = await licenseManager.activate(
                email: email,
                licenseKey: licenseKey
            )

            isActivating = false

            if success {
                showSuccess = true
                // Dismiss after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } else {
                errorMessage = "Invalid license key. Please check and try again."
            }
        }
    }
}

/// View for managing an existing license
struct LicenseManagementView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var licenseManager = LicenseManager.shared

    @State private var showDeactivateConfirm = false
    @State private var isDeactivating = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)

                Text("License Active")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let email = licenseManager.storedEmail {
                    Text("Licensed to: \(email)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // License info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(licenseManager.licenseState.statusMessage)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Activations:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("1 of \(PaddleConfig.maxActivations)")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Action buttons
            VStack(spacing: 12) {
                Button("Deactivate License") {
                    showDeactivateConfirm = true
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
        .alert("Deactivate License?", isPresented: $showDeactivateConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Deactivate", role: .destructive) {
                deactivateLicense()
            }
        } message: {
            Text("This will remove the license from this device. You can reactivate on another device or re-enter the key here.")
        }
    }

    private func deactivateLicense() {
        isDeactivating = true

        Task {
            _ = await licenseManager.deactivate()
            isDeactivating = false
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview("Activation") {
    LicenseActivationView()
}

#Preview("Management") {
    LicenseManagementView()
}
