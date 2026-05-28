//
//  CosmosStakingVerifySummaryView.swift
//  VultisigApp
//
//  Staking-aware verify summary for the four LUNA / LUNC operations.
//  Mirrors the desktop client's `StakeOverview.tsx` — the headline
//  changes per op ("You're staking / unstaking / moving / claiming"),
//  the destination is labeled as a validator (with resolved moniker +
//  commission), and redelegate renders two stacked rows (source then
//  destination).
//
//  Falls back to truncated valopers while the validators fetch is in
//  flight. The validators query is cached at `CosmosStakingService` for
//  read consistency with the picker.
//

import SwiftUI

struct CosmosStakingVerifySummaryView: View {
    let transaction: SendTransaction
    let vault: Vault
    let feeCrypto: String
    let feeFiat: String
    @Binding var securityScannerState: SecurityScannerState

    @State private var validatorsByAddress: [String: CosmosValidator] = [:]

    private let stakingService: CosmosStakingServiceProtocol

    init(
        transaction: SendTransaction,
        vault: Vault,
        feeCrypto: String,
        feeFiat: String,
        securityScannerState: Binding<SecurityScannerState>,
        stakingService: CosmosStakingServiceProtocol = CosmosStakingService()
    ) {
        self.transaction = transaction
        self.vault = vault
        self.feeCrypto = feeCrypto
        self.feeFiat = feeFiat
        self._securityScannerState = securityScannerState
        self.stakingService = stakingService
    }

    var body: some View {
        VStack(spacing: 16) {
            SecurityScannerHeaderView(state: securityScannerState)
            ScrollView {
                summary.padding(.top, 20)
            }
        }
        .task { await loadValidators() }
    }

    private var summary: some View {
        VStack(spacing: 16) {
            heroHeader
            Separator()

            getValueCell(for: "from", with: vault.name, bracketValue: transaction.fromAddress)
            Separator()

            validatorRows

            getValueCell(
                for: "network",
                with: transaction.coin.chain.name,
                image: transaction.coin.chain.logo
            )
            Separator()

            getValueCell(for: "estNetworkFee", with: feeCrypto, secondRowText: feeFiat)
        }
        .padding(24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(LinearGradient.borderGreen, lineWidth: 1)
        )
        .padding(1)
    }

    private var headlineKey: String {
        switch transaction.cosmosStakingPayload?.opType {
        case .delegate: return "youreStaking"
        case .undelegate: return "youreUnstaking"
        case .redelegate: return "youreMoving"
        case .withdrawRewards: return "youreClaiming"
        case .none: return "verify"
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 8) {
            Text(headlineKey.localized)
                .foregroundStyle(Theme.colors.textSecondary)
                .font(Theme.fonts.bodyMMedium)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Image(transaction.coin.logo)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .cornerRadius(32)

                Text(transaction.amountDecimal.formatForDisplay())
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(transaction.coin.ticker)
                    .foregroundStyle(Theme.colors.textTertiary)

                Spacer()
            }
            .font(Theme.fonts.bodyLMedium)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var validatorRows: some View {
        if let payload = transaction.cosmosStakingPayload {
            switch payload.opType {
            case .delegate, .undelegate:
                if let address = payload.validatorAddress {
                    getValueCell(for: "validator", with: resolveValidator(address))
                    Separator()
                }
            case .redelegate:
                if let src = payload.validatorSrcAddress {
                    getValueCell(for: "sourceValidator", with: resolveValidator(src))
                    Separator()
                }
                if let dst = payload.validatorDstAddress {
                    getValueCell(for: "destinationValidator", with: resolveValidator(dst))
                    Separator()
                }
            case .withdrawRewards:
                if let validators = payload.validators, !validators.isEmpty {
                    let label = validators.count == 1
                        ? resolveValidator(validators[0])
                        : String(format: "claimFromValidators".localized, validators.count)
                    getValueCell(for: "validator", with: label)
                    Separator()
                }
            }
        }
    }

    private func resolveValidator(_ valoper: String) -> String {
        guard let validator = validatorsByAddress[valoper] else {
            return truncated(valoper)
        }
        let display = validator.moniker.isEmpty ? truncated(valoper) : validator.moniker
        let pct = NSDecimalNumber(decimal: validator.commission * 100).intValue
        return "\(display) (\(pct)% \("commission".localized))"
    }

    private func truncated(_ value: String) -> String {
        guard value.count > 14 else { return value }
        return value.prefix(8) + "…" + value.suffix(4)
    }

    private func loadValidators() async {
        guard transaction.cosmosStakingPayload != nil else { return }
        do {
            let list = try await stakingService.fetchValidators(chain: transaction.coin.chain)
            validatorsByAddress = Dictionary(uniqueKeysWithValues: list.map { ($0.operatorAddress, $0) })
        } catch {
            // Resolver falls back to truncated valopers — user still sees a
            // distinguishable address rather than blank.
        }
    }

    private func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        secondRowText: String? = nil,
        image: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(title.localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(minWidth: 52, alignment: .leading)

            if let secondRowText {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                    Text(secondRowText)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if let bracketValue {
                HStack(spacing: 4) {
                    if let image {
                        Image(image)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    HStack(spacing: 4) {
                        Text(value)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        Text("(\(bracketValue))")
                            .foregroundStyle(Theme.colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    if let image {
                        Image(image)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(value)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: image == nil ? .infinity : nil, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
