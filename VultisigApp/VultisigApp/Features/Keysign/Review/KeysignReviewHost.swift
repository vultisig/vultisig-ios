//
//  KeysignReviewHost.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

extension View {
    /// Hosts the one keysign review sheet for everything this view contains,
    /// and puts its `KeysignReviewPresenter` in their environment.
    ///
    /// Must be applied inside `.environment(\.router, …)`. Applied outside it,
    /// this reads the default, detached `NavigationRouter`: the signing push
    /// would go nowhere and the sheet's content would not reach the stack.
    func keysignReviewHost() -> some View {
        modifier(KeysignReviewHost())
    }
}

private struct KeysignReviewHost: ViewModifier {
    /// Long enough for a pop's transition to finish, so a retry's review never
    /// rises over the signing screens as they leave.
    private static let navigationSettleDelay: Duration = .milliseconds(500)

    @Environment(\.router) private var router
    @State private var presenter = KeysignReviewPresenter()
    @State private var reopenTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(
                item: $presenter.presented,
                onDismiss: sheetDidDismiss,
                // Native macOS sheets can fail to composite Metal-backed
                // artwork. Keep Rive in the window's existing overlay host.
                useOverlayOnMacOS: true
            ) { review in
                KeysignReviewSheetContent(review: review, presentationID: presenter.presentationID)
                    .id(presenter.presentationID)
            }
            .onChange(of: presenter.isReopenPending) { _, isPending in
                guard isPending else { return }
                scheduleReopen()
            }
            .onReceive(router.$navPath) { _ in
                guard presenter.isReopenPending else { return }
                scheduleReopen()
            }
            .environment(presenter)
    }

    private func sheetDidDismiss() {
        presenter.sheetDidDismiss(router: router)
    }

    /// Restarted by every change to the path, so the review comes back only
    /// once the stack has been still for the settle delay, and the presenter
    /// then checks the signing screens are gone.
    private func scheduleReopen() {
        reopenTask?.cancel()
        reopenTask = Task { @MainActor in
            try? await Task.sleep(for: Self.navigationSettleDelay)
            guard !Task.isCancelled else { return }
            presenter.completeReopen(isShowingSigningRoute: router.isShowingSigningRoute)
        }
    }
}

/// The body of the review sheet, one per flow.
private struct KeysignReviewSheetContent: View {
    let review: KeysignReview
    let presentationID: UUID

    var body: some View {
        switch review {
        case .send(let tx, let retrySignal, let vault, let prebuiltKeysignPayload):
            SendReviewContent(
                transaction: tx,
                retrySignal: retrySignal,
                vault: vault,
                prebuiltKeysignPayload: prebuiltKeysignPayload,
                presentationID: presentationID
            )
        case .swap(let transaction, let retrySignal, let vaultPubKeyECDSA):
            // Swap carries the vault's key, not the live `@Model`, which is
            // resolved here on the main actor as its router does.
            if let vault = lookupVault(pubKeyECDSA: vaultPubKeyECDSA) {
                SwapReviewContent(
                    transaction: transaction,
                    retrySignal: retrySignal,
                    vault: vault,
                    presentationID: presentationID
                )
            }
        case .functionTransaction(let tx, let vault):
            FunctionTransactionReviewContent(transaction: tx, vault: vault, presentationID: presentationID)
        }
    }

    private func lookupVault(pubKeyECDSA: String) -> Vault? {
        guard let context = Storage.shared.modelContext else { return nil }
        let descriptor = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == pubKeyECDSA })
        return (try? context.fetch(descriptor))?.first
    }
}
