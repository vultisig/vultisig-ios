import SwiftUI

/// Presentation only: the owning screen keeps its content and navigation while
/// the routing view model resolves server presence.
struct FastVaultRoutingFeedback: View {
    let isChecking: Bool
    let hasError: Bool
    let onRetry: () -> Void
    let onPaired: () -> Void

    var body: some View {
        if isChecking || hasError {
            VStack(spacing: 16) {
                if isChecking {
                    ProgressView()
                }
                if hasError {
                    Text("errorNetworkUnstableTitle".localized)
                        .font(Theme.fonts.title2)
                    Text("errorNetworkUnstableDescription".localized)
                        .font(Theme.fonts.bodyMRegular)
                    PrimaryButton(title: "tryAgain".localized, action: onRetry)
                }
                PrimaryButton(title: "paired".localized, type: .secondary, action: onPaired)
            }
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
        }
    }
}
