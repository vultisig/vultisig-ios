//
//  SendCryptoVerifySummaryView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI

struct SendCryptoVerifySummaryView<ContentFooter: View>: View {
    let input: SendCryptoVerifySummary
    @Binding var securityScannerState: SecurityScannerState
    let contentPadding: CGFloat
    let contentFooter: () -> ContentFooter
    @State private var isTransactionDetailsExpanded: Bool = false

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

            Group {
                getValueCell(
                    for: "to",
                    with: input.toAlias ?? input.toAddress,
                    bracketValue: input.toAlias != nil ? input.toAddress : nil
                )
                Separator()
            }
            .showIf(input.toAddress.isNotEmpty)

            if shouldShowAmountRow, let tokenDisplay = input.tokenDisplay, !tokenDisplay.isEmpty {
                getValueCell(
                    for: "amount",
                    with: tokenDisplay,
                    color: input.tokenDisplayIsUnlimited ? Theme.colors.alertWarning : nil,
                    trailingIcon: input.tokenDisplayIsUnlimited ? "triangle-alert" : nil
                )
                Separator()
            }

            if hasTransactionDetails {
                transactionDetailsSection
                Separator()
            } else {
                Group {
                    getValueCell(for: "memo", with: input.memo, isMultiLine: true)
                    Separator()
                }
                .showIf(input.memo.isNotEmpty)
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

            Group {
                if let signDirect = input.keysignPayload?.signDirect {
                    Separator()
                    SignDirectDisplayView(signDirect: signDirect)
                } else if let signAmino = input.keysignPayload?.signAmino {
                    Separator()
                    SignAminoDisplayView(signAmino: signAmino)
                } else if let signSolana = input.keysignPayload?.signSolana {
                    Separator()
                    SignSolanaDisplayView(signSolana: signSolana)
                } else if let signTon = input.keysignPayload?.signTon,
                          let coin = input.keysignPayload?.coin,
                          let vault = input.vault {
                    Separator()
                    SignTonDisplayView(
                        signTon: signTon,
                        keysignPayload: input.keysignPayload,
                        vault: vault,
                        fromAddress: coin.address
                    )
                } else if let signBitcoin = input.keysignPayload?.signBitcoin {
                    Separator()
                    SignBitcoinDisplayView(signBitcoin: signBitcoin)
                } else if let signSui = input.keysignPayload?.signSui {
                    Separator()
                    SignSuiDisplayView(signSui: signSui)
                }
            }
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

    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        secondRowText: String? = nil,
        image: String? = nil,
        isMultiLine: Bool = false,
        color: Color? = nil,
        trailingIcon: String? = nil
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
                        Image(image)
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
                        Image(image)
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
                        Icon(named: trailingIcon, color: color ?? Theme.colors.alertWarning, size: 14)
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
        if let hero = input.hero {
            HeroContentView(content: hero)
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
        } else {
            VStack(spacing: 8) {
                Text(NSLocalizedString("youreSending", comment: ""))
                    .foregroundStyle(Theme.colors.textSecondary)
                    .font(Theme.fonts.bodyMMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Image(input.coinImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(32)

                    AmountText(input.amount)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text(input.coinTicker)
                        .foregroundStyle(Theme.colors.textTertiary)

                    Spacer()
                }
                .font(Theme.fonts.bodyLMedium)
            }
            .padding(.bottom, 8)
        }
    }

    var hasTransactionDetails: Bool {
        let hasSignature = !(input.decodedFunctionSignature?.isEmpty ?? true)
        let hasArguments = !(input.decodedFunctionArguments?.isEmpty ?? true)
        return hasSignature || hasArguments
    }

    var transactionDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isTransactionDetailsExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("transactionDetails".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isTransactionDetailsExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isTransactionDetailsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let signature = input.decodedFunctionSignature, !signature.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("functionSignature".localized)
                                    .foregroundStyle(Theme.colors.textTertiary)
                                    .font(Theme.fonts.bodySMedium)

                                Text(signature)
                                    .foregroundStyle(Theme.colors.turquoise)
                                    .font(Theme.fonts.bodySMedium)
                                    .textSelection(.enabled)
                            }
                        }

                        if let args = input.decodedFunctionArguments, !args.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("functionArguments".localized)
                                    .foregroundStyle(Theme.colors.textTertiary)
                                    .font(Theme.fonts.bodySMedium)

                                Text(args)
                                    .foregroundStyle(Theme.colors.turquoise)
                                    .font(Theme.fonts.bodySMedium)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }

    /// True when the hero doesn't already show a resolved amount/coin, so the
    /// "amount" detail row should render with the fallback `tokenDisplay` value.
    var shouldShowAmountRow: Bool {
        // signSui carries no to_amount; the value lives in the PTB bytes.
        if input.keysignPayload?.signSui != nil {
            return false
        }
        switch input.hero {
        case nil, .title:
            return true
        case .send, .swap:
            return false
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
                chainSpecific: .Cosmos(accountNumber: 3367086, sequence: 42, gas: 7500, transactionType: 0, ibcDenomTrace: nil),
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
