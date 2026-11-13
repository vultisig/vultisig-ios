//
//  PerpsReviewContent.swift
//  VultisigApp
//
//  Perps review, presented through the shared `KeysignReviewPresenter`
//  like send/swap/DeFi reviews: the shared `KeysignReviewSheet`, shared rows
//  and fee disclosure, and the standard `SigningCTAButtons`. one amount,
//  one caption, the rows needed to decide, one fee total. A live version would
//  `proceed(to:)` the shared `SigningRoute` with `VaultPerpsSigner`'s payload
//  per request. Until then the CTAs are disabled
//  (`PerpsConfig.allowsSigning == false`) and opening the review only records
//  the would-submit bodies in the dry-run client.
//

import SwiftUI
import VultisigUIResources

/// The Vultisig mark and a vault name on one line, cut at the end:
/// "Dev - consider funds lost (old laptop…". Same on the withdraw screen and its review.
struct PerpsVaultName: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            VultisigImage("vultisig-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(name)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Route-safe value for `KeysignReview.perps`: compared by identity, so
/// each presentation is distinct.
struct PerpsReviewRequest: Hashable {
    let id = UUID()
    let document: PerpsReviewDocument

    static func == (lhs: PerpsReviewRequest, rhs: PerpsReviewRequest) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PerpsReviewContent: View {
    let request: PerpsReviewRequest
    let vault: Vault

    @Environment(KeysignReviewPresenter.self) private var reviewPresenter
    @State private var didRecord = false

    private var document: PerpsReviewDocument { request.document }

    var body: some View {
        KeysignReviewSheet(
            title: document.sheetTitle,
            scanRing: .hidden,
            onClose: reviewPresenter.dismiss
        ) {
            VStack(spacing: 24) {
                hero
                // One compact group; fees and the signing account live in Details.
                VStack(spacing: 12) {
                    ForEach(Array((document.rows + document.trailingRows).enumerated()), id: \.offset) { index, row in
                        if index > 0 { KeysignReviewHairline() }
                        reviewRow(row)
                    }
                    KeysignReviewHairline()
                    KeysignReviewDisclosure(title: "perpsDetails".localized, value: "") {
                        ForEach(detailRows) { row in
                            KeysignReviewRow(label: row.label, value: row.value)
                        }
                    }
                }
                .padding(16)
                .background(Theme.radius.lg.shape.fill(Theme.colors.bgSurface1))
                if let footer = document.footer {
                    Text(footer)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, -12)
                }
                footnote
                if PerpsConfig.showsDebugDetails { debugDetails }
            }
            .frame(maxWidth: .infinity)
        } footer: {
            signingButtons
        }
        .onAppear(perform: recordDryRun)
    }

    /// The keysign payloads a live review would hand to the shared signing
    /// flow: every request signed at the trading-account path. Building them
    /// runs the same resolver keysign uses, so an unsupported vault is refused
    /// here, before anything starts.
    private var keysignPayloads: Result<[CustomMessagePayload], Error> {
        let signer = VaultPerpsSigner(vaultPublicKeyECDSA: vault.pubKeyECDSA, vaultLocalPartyID: vault.localPartyID, account: .trading)
        do {
            let payloads = try document.requests.compactMap { request -> CustomMessagePayload? in
                guard case let .vaultKeysign(payload, _) = try signer.prepare(request.signRequest) else { return nil }
                _ = try KeysignDerivationResolver.override(vault: vault, keysignType: .ECDSA, keysignPayload: nil, customMessagePayload: payload)
                return payload
            }
            return .success(payloads)
        } catch {
            return .failure(error)
        }
    }

    private var blockingIssue: String? {
        if let issue = document.blockingIssue { return issue }
        if case .failure(let error) = keysignPayloads { return error.localizedDescription }
        return nil
    }

    private var isSigningDisabled: Bool { !PerpsConfig.allowsSigning || blockingIssue != nil }

    /// The app's shared signing buttons (Paired + Fast Sign), unchanged.
    private var signingButtons: some View {
        SigningCTAButtons(isFastVault: vault.offersFastSigning, isDisabled: isSigningDisabled,
                          singleSignTitle: "signTransaction", onFastSign: {}, onPairedSign: {})
    }

    /// Label and value side by side when they fit, otherwise the value drops
    /// under its label. Nothing truncates or breaks mid-number.
    @ViewBuilder
    private func reviewRow(_ row: PerpsReviewRow) -> some View {
        if row.style == .vault {
            // A long vault name stays on one line and ends in "…"; the label keeps its width.
            HStack(spacing: 12) {
                Text(row.label).keysignReviewText(.footnote).foregroundStyle(Theme.colors.textTertiary).fixedSize()
                Spacer(minLength: 0)
                PerpsVaultName(name: row.value)
            }
        } else {
            plainRow(row)
        }
    }

    private func plainRow(_ row: PerpsReviewRow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(row.label).keysignReviewText(.footnote).foregroundStyle(Theme.colors.textTertiary).fixedSize()
                Spacer(minLength: 8)
                Text(row.value).keysignReviewText(.bodyS).monospacedDigit().foregroundStyle(row.color).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.label).keysignReviewText(.footnote).foregroundStyle(Theme.colors.textTertiary)
                Text(row.value).keysignReviewText(.bodyS).foregroundStyle(row.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            if let label = document.amountLabel {
                Text(label)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            if !document.amount.isEmpty {
                Text(document.amount)
                    .font(Theme.fonts.priceLargeTitle)
                    .monospacedDigit()
                    .foregroundStyle(document.amountTone.map { PerpsReviewRow(label: "", value: "", tone: $0).color } ?? Theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text(document.caption)
                .font(document.amount.isEmpty ? Theme.fonts.bodyMMedium : Theme.fonts.bodySRegular)
                .foregroundStyle(document.amount.isEmpty ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                .multilineTextAlignment(.center)
            if let note = document.note {
                Text(note)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// The margin actually used and the fee total (together they reconcile
    /// the amount entered), then who signs ("Trading account 0x3868…3533"). A
    /// deposit lists its fee parts (different payees), and so does a VULT discount
    /// ("Vultisig 0.1% $0.20", "VULT Gold: 40% −$0.08"), so the total adds up.
    private var detailRows: [PerpsReviewRow] {
        var rows: [PerpsReviewRow] = document.detailRows
        if let fees = document.fees {
            rows.append(PerpsReviewRow(label: "perpsFees".localized, value: fees.total))
            if document.deposit != nil || fees.showsBreakdown { rows += fees.breakdown }
        }
        rows.append(signingRow)
        return rows
    }

    /// Only what blocks the review, if anything.
    @ViewBuilder
    private var footnote: some View {
        if let issue = blockingIssue {
            Text(issue)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.alertError)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("perpsReviewFootnote")
        }
    }

    /// "Trading account  0x3868…3533"; a deposit is signed by the vault itself.
    private var signingRow: PerpsReviewRow {
        let context = PerpsVaultContext(vault: vault)
        guard !document.requests.isEmpty, let trading = context.tradingAddress else {
            return PerpsReviewRow(label: "perpsSigning".localized, value: vault.name)
        }
        return PerpsReviewRow(label: "perpsTradingAccountShort".localized, value: PerpsFormat.shortAddress(trading))
    }

    /// Debug only: what each vault approval would sign.
    private var debugDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let deposit = document.deposit {
                Text("receiveWithAuthorization 0x\(deposit.authorization.digest.hexString)")
                Text("cctp hookData 0x\(deposit.hookData.hexString)")
            }
            ForEach(Array(document.requests.enumerated()), id: \.offset) { _, request in
                Text("\(request.kind.rawValue) 0x\(request.digest.hexString)")
            }
            if let note = document.debugNote { Text(note) }
            if case .success(let payloads) = keysignPayloads, !payloads.isEmpty {
                Text("keysign payloads ready: \(payloads.count) at \(payloads[0].derivePath ?? "default")")
            }
        }
        .font(Theme.fonts.caption10)
        .foregroundStyle(Theme.colors.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func recordDryRun() {
        guard !didRecord else { return }
        didRecord = true
        if let deposit = document.deposit { HyperliquidExchangeDryRunClient.shared.recordDeposit(deposit) }
        HyperliquidExchangeDryRunClient.shared.submit(document.requests)
    }
}
