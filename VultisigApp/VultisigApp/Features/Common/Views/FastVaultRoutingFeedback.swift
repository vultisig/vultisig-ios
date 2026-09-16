import SwiftUI

enum FastVaultRoutingState {
    case idle
    case checking
    case failed
}

/// Presentation only; the screen owns the async lookup and navigation.
struct FastVaultRoutingFeedback: View {
    let state: FastVaultRoutingState
    let onRetry: () -> Void
    let onPaired: () -> Void

    var body: some View {
        if state != .idle {
            VStack(spacing: 16) {
                if state == .checking {
                    ProgressView()
                }
                if state == .failed {
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
