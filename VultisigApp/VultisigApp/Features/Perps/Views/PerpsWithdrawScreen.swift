//
//  PerpsWithdrawScreen.swift
//  VultisigApp
//
//  Perps 16.01: withdraw from the trading account to the vault.
//  The amount comes from a keypad (dot decimals in every locale), Max is the
//  server's `withdrawable`, and "You receive" is net of every fee. Review
//  opens the shared keysign review sheet (16.02).
//

import SwiftUI
import VultisigUIResources

struct PerpsWithdrawScreen: View {
    let vault: Vault

    @StateObject private var loader = PerpsHubViewModel()
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter
    @Environment(\.router) private var router
    @State private var didPresentReview = false

    var body: some View {
        Screen {
            if let account = loader.account {
                PerpsWithdrawContent(account: account, vault: PerpsVaultContext(vault: vault),
                                     prefill: demoPrefill) { document in
                    didPresentReview = true
                    reviewPresenter.present(.perps(request: PerpsReviewRequest(document: document), vaultPubKeyECDSA: vault.pubKeyECDSA))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenTitle("perpsWithdraw".localized)
        .perpsScreenMargins()
        .task { await loader.load(vault: vault) }
        // Debug story only: closing the review stands in for signing it; the hub shows Withdrawing.
        .onChange(of: reviewPresenter.presented == nil) { _, isClosed in
            guard isClosed, didPresentReview else { return }
            didPresentReview = false
            #if DEBUG
            guard PerpsDemoStory.isOn, PerpsDemoStory.stage == .opened else { return }
            PerpsDemoStory.stage = .withdrawn
            PerpsDemoStory.markWithdrawingPending()
            router.navigateBack()
            #endif
        }
    }

    private var demoPrefill: Decimal? {
        #if DEBUG
        PerpsDemoState.current.contains(.withdraw) ? PerpsDemoRepository.demoWithdrawal : nil
        #else
        nil
        #endif
    }
}

private struct PerpsWithdrawContent: View {
    @StateObject private var viewModel: PerpsWithdrawViewModel
    let onReview: (PerpsReviewDocument) -> Void

    init(account: PerpsAccountSnapshot, vault: PerpsVaultContext, prefill: Decimal?, onReview: @escaping (PerpsReviewDocument) -> Void) {
        _viewModel = StateObject(wrappedValue: PerpsWithdrawViewModel(account: account, vault: vault, prefill: prefill))
        self.onReview = onReview
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: PerpsLayout.section) {
                amount
                details
            }
            .padding(.top, 20)
            Spacer(minLength: 16)
            PrimaryButton(title: "perpsReview".localized) {
                guard let document = viewModel.reviewDocument() else { return }
                onReview(document)
            }
            .disabled(!viewModel.canReview)
            .accessibilityIdentifier("perpsWithdrawReview")
            PerpsKeypad(onPress: viewModel.press)
                .padding(.top, 12)
        }
    }

    private var amount: some View {
        VStack(spacing: 10) {
            PerpsKeypadAmount(text: viewModel.amountText, accessibilityID: "perpsWithdrawAmount")
            HStack(spacing: 8) {
                Text(viewModel.issue ?? String(format: "perpsAvailableAmount".localized,
                                               PerpsFormat.usd(viewModel.account.availableToWithdraw)))
                    .font(Theme.fonts.bodySRegular)
                    .monospacedDigit()
                    .foregroundStyle(viewModel.issue == nil ? Theme.colors.textTertiary : Theme.colors.alertError)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if viewModel.issue == nil {
                    PrimaryButton(title: "perpsMax".localized, type: .secondary, size: .mini) { viewModel.applyMax() }
                        .fixedSize()
                        .accessibilityIdentifier("perpsWithdrawMax")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "To" with the vault on one truncating line, then what arrives.
    private var details: some View {
        PerpsCard {
            HStack(spacing: 12) {
                Text("perpsTo".localized)
                    .font(Theme.fonts.subtitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .fixedSize()
                Spacer(minLength: 0)
                PerpsVaultName(name: viewModel.vault.name)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .accessibilityElement(children: .combine)
            PerpsRow(title: "perpsYouReceive".localized, value: PerpsFormat.usd(viewModel.quote.receive), showsDivider: true)
        }
    }
}

/// The amount a `PerpsKeypad` types: "$0" greyed when empty, "$12.50" after.
struct PerpsKeypadAmount: View {
    let text: String
    let accessibilityID: String

    var body: some View {
        Text(text.isEmpty ? "$0" : "$" + text)
            .font(Theme.fonts.priceLargeTitle)
            .monospacedDigit()
            .foregroundStyle(text.isEmpty ? Theme.colors.textTertiary : Theme.colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(accessibilityID)
    }
}

/// Digits, a dot and delete. The dot is always ".", so amounts never pick up
/// a locale's comma.
struct PerpsKeypad: View {
    let onPress: (PerpsKeypadKey) -> Void

    private let rows: [[PerpsKeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.dot, .digit(0), .delete]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { key in
                        Button { onPress(key) } label: {
                            label(key)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(identifier(key))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func label(_ key: PerpsKeypadKey) -> some View {
        switch key {
        case .digit(let digit):
            Text("\(digit)").font(Theme.fonts.keypadDigit).foregroundStyle(Theme.colors.textPrimary)
        case .dot:
            Text(".").font(Theme.fonts.keypadDigit).foregroundStyle(Theme.colors.textPrimary)
        case .delete:
            Image(systemName: "delete.left").font(Theme.fonts.keypadGlyph).foregroundStyle(Theme.colors.textPrimary)
                .accessibilityLabel("perpsDelete".localized)
        }
    }

    private func identifier(_ key: PerpsKeypadKey) -> String {
        switch key {
        case .digit(let digit): return "perpsKey-\(digit)"
        case .dot: return "perpsKey-dot"
        case .delete: return "perpsKey-delete"
        }
    }
}
