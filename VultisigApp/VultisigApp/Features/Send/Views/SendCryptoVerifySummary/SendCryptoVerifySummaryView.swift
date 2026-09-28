//
//  SendCryptoVerifySummaryView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI
import VultisigUIResources

struct SendCryptoVerifySummaryView<ContentFooter: View>: View {
    let input: SendCryptoVerifySummary
    @Binding var securityScannerState: SecurityScannerState
    let contentPadding: CGFloat
    let contentFooter: () -> ContentFooter

    init(input: SendCryptoVerifySummary, securityScannerState: Binding<SecurityScannerState>, contentPadding: CGFloat = 0) where ContentFooter == EmptyView {
        self.input = input
        self._securityScannerState = securityScannerState
        self.contentPadding = contentPadding
        self.contentFooter = { EmptyView() }
    }

    init(input: SendCryptoVerifySummary, securityScannerState: Binding<SecurityScannerState>, contentPadding: CGFloat = 0, @ViewBuilder contentFooter: @escaping () -> ContentFooter) {
        self.input = input
        self._securityScannerState = securityScannerState
        self.contentPadding = contentPadding
        self.contentFooter = contentFooter
    }

    var body: some View {
        VStack(spacing: 16) {
            securityScannerHeader
            fields
        }
    }

    var securityScannerHeader: some View {
        SecurityScannerHeaderView(state: securityScannerState)
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
                contentFooter()
            }
            .padding(.horizontal, contentPadding)
        }
        .padding(.top, 20)
    }

    var summary: some View {
        VStack(spacing: 16) {
            if let metadata = input.dappMetadata, !metadata.isEmpty {
                DAppRequestBanner(metadata: metadata)
            }
            heroHeader
            Separator()

            Group {
                getValueCell(for: "from", with: input.fromName, bracketValue: input.fromAddress)
                Separator()
            }
            .showIf(input.fromAddress.isNotEmpty)

            // An XRPL TrustSet opens a trust line: it has no destination and no
            // transfer amount, so it gets its own rows instead of the Payment
            // ones. A "to" row would name an account this transaction never pays,
            // and an "amount" row would present a trust-line LIMIT as if funds
            // were moving. Dispatched here — the one view both the initiator's
            // Verify screen and a co-signer's Join screen render — so a peer
            // device can never be shown Payment framing for a trust line.
            if input.isRippleTrustSet {
                Group {
                    if let trustSet = input.reviewableRippleTrustSet {
                        getValueCell(for: "rippleTrustLineIssuer", with: trustSet.issuer)
                        Separator()
                        getValueCell(for: "rippleTrustLineCurrency", with: trustSet.ticker)
                        Separator()
                        getValueCell(for: "rippleTrustLineLimit", with: "\(trustSet.limitValue) \(trustSet.ticker)")
                        Separator()
                    } else {
                        // A TrustSet whose terms cannot be read. Say so instead of
                        // borrowing the Payment rows, which would present the
                        // limit as a transfer to `toAddress`. The signer refuses
                        // these payloads as well, so this is a dead end by design.
                        getValueCell(
                            for: "rippleTrustLineUnreviewable",
                            with: "rippleTrustLineUnreviewableValue".localized,
                            isMultiLine: true,
                            color: Theme.colors.alertError
                        )
                        Separator()
                    }
                }
            } else {
                Group {
                    getValueCell(
                        for: "to",
                        with: input.toAlias ?? input.toAddress,
                        bracketValue: input.toAlias != nil ? input.toAddress : nil
                    )
                    Separator()
                }
                .showIf(input.toAddress.isNotEmpty)
            }

            // Which vault the address above actually is, and who curates it —
            // read out of the bytes, not out of the request. In the normal row
            // list rather than a section of their own: they identify the
            // destination, which is what the rows around them are for.
            if let kamino = input.kaminoState.display {
                getValueCell(for: "kaminoVerifyVault", with: kamino.vaultName)
                Separator()
                getValueCell(for: "kaminoVerifyCurator", with: kamino.curatorWithRiskTier)
                Separator()
            }

            if input.shouldShowAmountRow, let tokenDisplay = input.tokenDisplay, !tokenDisplay.isEmpty {
                getValueCell(
                    for: "amount",
                    with: tokenDisplay,
                    color: input.tokenDisplayIsUnlimited ? Theme.colors.alertWarning : nil,
                    trailingIcon: input.tokenDisplayIsUnlimited ? .triangleWarning : nil
                )
                Separator()
            }

            if input.hasTransactionDetails {
                SendTransactionDetailsSection(input: input)
                Separator()
            } else {
                Group {
                    getValueCell(for: "memo", with: input.memo, isMultiLine: true)
                    Separator()
                }
                .showIf(input.memo.isNotEmpty)
            }

            if let destinationTag = input.destinationTag, destinationTag.isNotEmpty {
                getValueCell(for: "destinationTag", with: destinationTag)
                Separator()
            }

            if let dictionary = input.memoFunctionDictionary, !dictionary.isEmpty {
                ForEach(Array(dictionary.keys), id: \.self) { key in
                    if let value = dictionary[key] {
                        getValueCell(for: key, with: value)
                        Separator()
                    }
                }
            }

            getValueCell(for: "network", with: input.network, image: input.networkImage)
            Separator()

            getValueCell(for: "estNetworkFee", with: input.feeCrypto, secondRowText: input.feeFiat)
                .blur(radius: input.isCalculatingFee ? 1 : 0)

            // Costs the fee row cannot express — see `additionalRows`. Placed
            // directly under it because that is what they are: part of what this
            // transaction costs, read in the same breath.
            ForEach(input.additionalRows) { row in
                Separator()
                getValueCell(for: row.title, with: row.value)
            }

            // What the decode has left to say once the vault, curator and action
            // are already rows above: a withdraw's share figure, and anything
            // this transaction needs to warn about. Placed ahead of the
            // raw-transaction disclosure and outside it, because a co-signer must
            // not have to expand anything to learn that a decode disagreed with
            // the summary — that is a refusal, not a detail.
            //
            // Gated on `hasVisibleDetail` rather than on "is this Kamino": a
            // verified deposit has nothing further to report, and rendering it
            // anyway leaves a separator and an empty band under the fee row.
            //
            // Bound once: the decode parses the wire message and derives the
            // signer's share account for each curated vault, so reading the
            // property twice per render would do that work twice.
            let kamino = input.kaminoState
            Group {
                if kamino.hasVisibleDetail {
                    Separator()
                    KaminoVerifyDetailView(state: kamino)
                }
            }

            Group {
                let decodedPayload = DecodedPayloadDetailView(payload: input.keysignPayload, vault: input.vault)
                if decodedPayload.hasContent {
                    Separator()
                }
                decodedPayload
            }
        }
        .padding(24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(Theme.radius.xl)
        .overlay(
            Theme.radius.xl.shape
                .stroke(LinearGradient.borderGreen, lineWidth: 1)
        )
        .padding(1)
    }

    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        secondRowText: String? = nil,
        image: String? = nil,
        isMultiLine: Bool = false,
        color: Color? = nil,
        trailingIcon: ImageResource? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(title.localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(minWidth: 52, alignment: .leading)

            if let secondRowText {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .foregroundStyle(color ?? Theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(secondRowText)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if let bracketValue {
                HStack(spacing: 4) {
                    if let image {
                        VultisigImage(image)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    HStack(spacing: 4) {
                        Text(value)
                            .foregroundStyle(color ?? Theme.colors.textPrimary)
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
                        VultisigImage(image)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(value)
                        .foregroundStyle(color ?? Theme.colors.textPrimary)
                        .lineLimit(isMultiLine ? nil : 1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: image == nil ? .infinity : nil, alignment: .trailing)
                    if let trailingIcon {
                        Icon(trailingIcon, color: color ?? Theme.colors.alertWarning, size: 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var heroHeader: some View {
        // Checked BEFORE `input.hero`: the Join screen derives its hero from a
        // transaction simulation, which reads a TrustSet as an ordinary send. A
        // co-signer must not be shown "You're sending <limit> <ticker>" for a
        // transaction that moves nothing.
        if input.isRippleTrustSet {
            // Nothing is being sent — a trust line is being opened. When the
            // terms are unreadable the header stays generic rather than naming a
            // ticker we couldn't decode.
            Text(
                input.reviewableRippleTrustSet.map { String(format: "rippleTrustLineHeroTitle".localized, $0.ticker) }
                    ?? "rippleTrustLineActivationTitle".localized
            )
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyMMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        } else if let hero = input.hero {
            VerifyHeroContentView(content: hero)
                .padding(.bottom, 8)
        } else if input.keysignPayload?.signSui != nil {
            // signSui payloads carry no to_address / to_amount — the amount is
            // baked into the PTB bytes. Show a neutral title instead of a
            // misleading "0 SUI" send card; the decoded PTB renders below.
            Text("suiTransaction".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyMMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
        } else if input.keysignPayload?.signRipple != nil {
            // signRipple carries the dApp transaction in raw JSON — an
            // OfferCreate or cross-currency Payment has no simple to_amount to
            // show. Use a neutral title; the decoded terms render below.
            Text("rippleTransaction".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyMMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
        } else {
            VStack(spacing: 8) {
                // A Kamino transaction says what it is here rather than "you're
                // sending", which describes a transfer and is the one thing a
                // vault deposit is not.
                Text(input.kaminoState.display?.headerTitle ?? NSLocalizedString("youreSending", comment: ""))
                    .foregroundStyle(Theme.colors.textSecondary)
                    .font(Theme.fonts.bodyMMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    // `Image(_:)` resolves a bundled asset by name and renders
                    // nothing when there is no such asset. Native coins ship one;
                    // a token's `logo` is a remote URL, so every SPL/ERC-20 send
                    // drew a blank square here. `AsyncImageView` handles both and
                    // falls back to the ticker rather than to empty space.
                    AsyncImageView(
                        logo: input.coinImage,
                        size: CGSize(width: 24, height: 24),
                        ticker: input.coinTicker,
                        tokenChainLogo: nil
                    )

                    CoinAmountFiatLabel(
                        amount: input.amount,
                        ticker: input.coinTicker,
                        fiat: input.amountFiat
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

#Preview("Without SignData") {
    SendCryptoVerifySummaryView(
        input: SendCryptoVerifySummary(
            fromName: "My Vault",
            fromAddress: "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z",
            toAddress: "thor1zgmsl5g25mfrtyuyrgdxh7r35wyyreh3p89jgq",
            network: "THORChain",
            networkImage: "thorchain",
            memo: "test memo",
            feeCrypto: "0.02 RUNE",
            feeFiat: "US$ 0.10",
            coinImage: "rune",
            amount: "30",
            amountFiat: "US$ 90.00",
            coinTicker: "RUNE",
            keysignPayload: nil
        ),
        securityScannerState: .constant(.idle)
    )
}

#Preview("With SignDirect") {
    SendCryptoVerifySummaryView(
        input: SendCryptoVerifySummary(
            fromName: "My Vault",
            fromAddress: "thor1zgmsl5g25mfrtyuyrgdxh7r35wyyreh3p89jgq",
            toAddress: "",
            network: "THORChain",
            networkImage: "thorchain",
            memo: "secure-:ltc1qc56q990vzj3a89d544dvj28grrpxqq0pw64hq4",
            feeCrypto: "0.02 RUNE",
            feeFiat: "US$ 0.10",
            coinImage: "ltc",
            amount: "0.03",
            amountFiat: "US$ 2.60",
            coinTicker: "LTC",
            keysignPayload: KeysignPayload(
                coin: .example,
                toAddress: "",
                toAmount: 3000000,
                chainSpecific: .THORChain(accountNumber: 139521, sequence: 392, fee: 2000000, isDeposit: false, transactionType: 0),
                utxos: [],
                memo: "secure-:ltc1qc56q990vzj3a89d544dvj28grrpxqq0pw64hq4",
                swapPayload: nil,
                approvePayload: nil,
                vaultPubKeyECDSA: "03a4d9b5d643f9a08846295e3010b26fe37c12611020853d526b96cdd0e09d12af",
                vaultLocalPartyID: "iPhone-100",
                libType: LibType.DKLS.toString(),
                wasmExecuteContractPayload: nil,
                tronTransferContractPayload: nil,
                tronTriggerSmartContractPayload: nil,
                tronTransferAssetContractPayload: nil,
                qbtcClaimPayload: nil,
                isQbtcClaim: false,
                skipBroadcast: false,
                signData: .signDirect(SignDirect(
                    bodyBytes: "CoQBChEvdHlwZXMuTXNnRGVwb3NpdBJvCiIKFQoDTFRDEgNMVEMaA0xUQyAAKAAwARIHMzAwMDAwMBgAEjNzZWN1cmUtOmx0YzFxYzU2cTk5MHZ6ajNhODlkNTQ0ZHZqMjhncnJweHFxMHB3NjRocTQaFBI3D9EKptI1k4QaGmv4caOIQebx",
                    authInfoBytes: "ClEKRgofL2Nvc21vcy5jcnlwdG8uc2VjcDI1NmsxLlB1YktleRIjCiED0PoXq6fLV8K/5DCOp6flUifi79nV3bW9c+MzV8tm4eoSBAoCCAEYiAMSEgoMCgRydW5lEgQxMDAwEMCaDA==",
                    chainID: "thorchain-1",
                    accountNumber: "139521"
                ))
            )
        ),
        securityScannerState: .constant(.idle)
    )
}

#Preview("With SignAmino") {
    SendCryptoVerifySummaryView(
        input: SendCryptoVerifySummary(
            fromName: "My Vault",
            fromAddress: "cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas",
            toAddress: "cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas",
            network: "Cosmos",
            networkImage: "cosmos",
            memo: "",
            feeCrypto: "0.001 ATOM",
            feeFiat: "US$ 0.01",
            coinImage: "atom",
            amount: "0.006",
            coinTicker: "ATOM",
            keysignPayload: KeysignPayload(
                coin: .example,
                toAddress: "cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas",
                toAmount: 0,
                chainSpecific: .Cosmos(accountNumber: 3367086, sequence: 42, gas: 7500, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil),
                utxos: [],
                memo: nil,
                swapPayload: nil,
                approvePayload: nil,
                vaultPubKeyECDSA: "03a4d9b5d643f9a08846295e3010b26fe37c12611020853d526b96cdd0e09d12af",
                vaultLocalPartyID: "iPhone-100",
                libType: LibType.DKLS.toString(),
                wasmExecuteContractPayload: nil,
                tronTransferContractPayload: nil,
                tronTriggerSmartContractPayload: nil,
                tronTransferAssetContractPayload: nil,
                qbtcClaimPayload: nil,
                isQbtcClaim: false,
                skipBroadcast: true,
                signData: .signAmino(SignAmino(
                    fee: CosmosFee(
                        payer: "",
                        granter: "",
                        feePayer: "",
                        amount: [CosmosCoin(amount: "1000", denom: "uatom")],
                        gas: "200000"
                    ),
                    msgs: [
                        CosmosMessage(
                            type: "cosmos-sdk/MsgSend",
                            value: "{\"amount\":[{\"amount\":\"1000\",\"denom\":\"uatom\"}],\"from_address\":\"cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas\",\"to_address\":\"cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas\"}"
                        ),
                        CosmosMessage(
                            type: "cosmos-sdk/MsgSend",
                            value: "{\"amount\":[{\"amount\":\"2000\",\"denom\":\"uatom\"}],\"from_address\":\"cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas\",\"to_address\":\"cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas\"}"
                        ),
                        CosmosMessage(
                            type: "cosmos-sdk/MsgSend",
                            value: "{\"amount\":[{\"amount\":\"3000\",\"denom\":\"uatom\"}],\"from_address\":\"cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas\",\"to_address\":\"cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas\"}"
                        )
                    ]
                ))
            )
        ),
        securityScannerState: .constant(.idle)
    )
}
