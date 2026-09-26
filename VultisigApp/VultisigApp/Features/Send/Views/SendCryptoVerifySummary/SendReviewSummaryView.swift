//
//  SendReviewSummaryView.swift
//  VultisigApp
//
//  The send summary as the initiator's review sheet lays it out. It shows the
//  same fields as `SendCryptoVerifySummaryView`, which the joining co-signer
//  still sees full screen, and takes the same decisions from
//  `SendCryptoVerifySummary`.
//

import SwiftUI

struct SendReviewSummaryView: View {
    let input: SendCryptoVerifySummary

    var body: some View {
        VStack(spacing: 20) {
            if let metadata = input.dappMetadata, !metadata.isEmpty {
                DAppRequestBanner(metadata: metadata)
            }

            hero

            if showsAddressCards {
                KeysignReviewAddressCards(
                    from: KeysignReviewParty(name: input.fromName, address: input.fromAddress),
                    to: KeysignReviewParty(name: input.toAlias, address: input.toAddress)
                )
            }

            rows
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        // Checked before `input.hero`, as on the co-signer's summary: a
        // simulated hero reads a TrustSet as an ordinary send.
        if input.isRippleTrustSet {
            heroTitle(
                input.reviewableRippleTrustSet.map { String(format: "rippleTrustLineHeroTitle".localized, $0.ticker) }
                    ?? "rippleTrustLineActivationTitle".localized
            )
        } else if let hero = input.hero {
            VerifyHeroContentView(content: hero)
        } else if input.keysignPayload?.signSui != nil {
            heroTitle("suiTransaction".localized)
        } else if input.keysignPayload?.signRipple != nil {
            heroTitle("rippleTransaction".localized)
        } else {
            VStack(spacing: 12) {
                // A Kamino transaction says what it is; a plain transfer needs
                // no caption over its amount.
                if let title = input.kaminoState.display?.headerTitle {
                    Text(title)
                        .keysignReviewText(.bodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                KeysignReviewAmountHero(
                    logo: input.coinImage,
                    ticker: input.coinTicker,
                    amount: input.amount,
                    fiat: input.amountFiat
                )
            }
        }
    }

    private func heroTitle(_ title: String) -> some View {
        Text(title)
            .keysignReviewText(.title3)
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Parties

    /// A transfer names both ends on cards. A TrustSet pays no one, so it
    /// never gets them; what it sets up is listed in the rows instead.
    private var showsAddressCards: Bool {
        !input.isRippleTrustSet && input.fromAddress.isNotEmpty && input.toAddress.isNotEmpty
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: 12) {
            if !showsAddressCards, input.fromAddress.isNotEmpty {
                KeysignReviewRow(label: "from".localized) {
                    namedAddress(name: input.fromName, address: input.fromAddress)
                }
            }

            KeysignReviewRow(label: "network".localized, value: input.network, image: input.networkImage)

            if input.isRippleTrustSet {
                trustSetRows
            } else if !showsAddressCards, input.toAddress.isNotEmpty {
                KeysignReviewRow(label: "to".localized) {
                    namedAddress(name: input.toAlias, address: input.toAddress)
                }
            }

            if input.hasTransactionDetails {
                SendTransactionDetailsSection(input: input)
            } else if input.memo.isNotEmpty {
                KeysignReviewRow(label: "memo".localized, value: input.memo, isMultiline: true)
            }

            if let destinationTag = input.destinationTag, destinationTag.isNotEmpty {
                KeysignReviewRow(label: "destinationTag".localized, value: destinationTag)
            }

            if let dictionary = input.memoFunctionDictionary, !dictionary.isEmpty {
                ForEach(Array(dictionary.keys), id: \.self) { key in
                    if let value = dictionary[key] {
                        KeysignReviewRow(label: key.localized, value: value)
                    }
                }
            }

            // Which vault the recipient actually is, and who curates it — read
            // out of the bytes, not out of the request.
            if let kamino = input.kaminoState.display {
                KeysignReviewRow(label: "kaminoVerifyVault".localized, value: kamino.vaultName)
                KeysignReviewRow(label: "kaminoVerifyCurator".localized, value: kamino.curatorWithRiskTier)
            }

            if input.shouldShowAmountRow, let tokenDisplay = input.tokenDisplay, !tokenDisplay.isEmpty {
                KeysignReviewRow(label: "amount".localized) {
                    HStack(spacing: 4) {
                        Text(tokenDisplay)
                            .keysignReviewText(.bodyS)
                            .foregroundStyle(input.tokenDisplayIsUnlimited ? Theme.colors.alertWarning : Theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if input.tokenDisplayIsUnlimited {
                            Icon(.triangleWarning, color: Theme.colors.alertWarning, size: 14)
                        }
                    }
                }
            }

            KeysignReviewHairline()

            KeysignReviewFeeRow(label: "estNetworkFee".localized, amount: input.feeCrypto, fiat: input.feeFiat)
                .blur(radius: input.isCalculatingFee ? 1 : 0)

            // Costs the fee row cannot express, read in the same breath as it.
            ForEach(input.additionalRows) { row in
                KeysignReviewRow(label: row.title.localized, value: row.value)
            }

            // A decode disagreeing with the summary is a refusal, not a detail,
            // so it sits outside any disclosure.
            let kamino = input.kaminoState
            if kamino.hasVisibleDetail {
                KaminoVerifyDetailView(state: kamino)
            }

            decodedPayload
        }
    }

    @ViewBuilder
    private var trustSetRows: some View {
        if let trustSet = input.reviewableRippleTrustSet {
            KeysignReviewRow(label: "rippleTrustLineIssuer".localized, value: trustSet.issuer)
            KeysignReviewRow(label: "rippleTrustLineCurrency".localized, value: trustSet.ticker)
            KeysignReviewRow(label: "rippleTrustLineLimit".localized, value: "\(trustSet.limitValue) \(trustSet.ticker)")
        } else {
            // Terms that cannot be read are said to be unreadable rather than
            // borrowing the Payment rows. The signer refuses these payloads too.
            KeysignReviewRow(
                label: "rippleTrustLineUnreviewable".localized,
                value: "rippleTrustLineUnreviewableValue".localized,
                color: Theme.colors.alertError,
                isMultiline: true
            )
        }
    }

    private var decodedPayload: some View {
        DecodedPayloadDetailView(payload: input.keysignPayload, vault: input.vault)
    }

    private func namedAddress(name: String?, address: String) -> some View {
        HStack(spacing: 4) {
            if let name, name.isNotEmpty {
                Text(name)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .layoutPriority(1)
            }
            Text(name == nil ? address : "(\(address))")
                .foregroundStyle(name == nil ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                .truncationMode(.middle)
        }
        .keysignReviewText(.bodyS)
        .lineLimit(1)
    }
}
