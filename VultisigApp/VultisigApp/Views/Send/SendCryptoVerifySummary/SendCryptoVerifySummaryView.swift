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
            summaryTitle
            summaryCoinDetails
            Separator()
            
            Group {
                getValueCell(for: "from", with: input.fromName, bracketValue: input.fromAddress)
                Separator()
            }
            .showIf(input.fromAddress.isNotEmpty)
            
            Group {
                getValueCell(for: "to", with: input.toAddress)
                Separator()
            }
            .showIf(input.toAddress.isNotEmpty)
            
            if let signature = input.decodedFunctionSignature, !signature.isEmpty {
                getValueCell(for: "functionSignature", with: signature, isMultiLine: true, color: Theme.colors.turquoise)
                Separator()
                
                if let args = input.decodedFunctionArguments, !args.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("functionArguments", comment: ""))
                            .foregroundColor(Theme.colors.textTertiary)
                            .font(Theme.fonts.bodySMedium)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(args)
                                .foregroundColor(Theme.colors.turquoise)
                                .font(Theme.fonts.bodySMedium)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Separator()
                }
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
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreSending", comment: ""))
            .foregroundColor(Theme.colors.textSecondary)
            .font(Theme.fonts.bodyMMedium)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var summaryCoinDetails: some View {
        HStack(spacing: 8) {
            Image(input.coinImage)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(32)
            
            Text(input.amount)
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(input.coinTicker)
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
        }
        .font(Theme.fonts.bodyLMedium)
    }
    
    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        secondRowText: String? = nil,
        image: String? = nil,
        isMultiLine: Bool = false,
        color: Color? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
            
            if let image {
                Image(image)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundColor(color ?? Theme.colors.textPrimary)
                    .lineLimit(isMultiLine ? nil : 1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let secondRowText {
                    Text(secondRowText)
                        .foregroundColor(Theme.colors.textTertiary)
                }
            }
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            
        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
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
