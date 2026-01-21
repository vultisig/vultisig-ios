//
//  SendCryptoSecondaryDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-09.
//

import SwiftUI
import SwiftData

struct SendCryptoSecondaryDoneView: View {
    @Environment(\.router) var router
    let input: SendCryptoContent

    @State var navigateToAddressBook = false
    @Environment(\.openURL) var openURL
    @State var canShowAddressBook: Bool = false
    @State var addressCountBeforeNavigation: Int = 0

    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var appViewModel: AppViewModel

    var showAddressBookButton: Bool {
        input.isSend && canShowAddressBook
    }

    var body: some View {
        Screen(title: "transactionDetails".localized) {
            VStack {
                ScrollView {
                    VStack {
                        header
                        summary
                    }
                    .padding(.vertical, 24)
                }

                continueButton
            }
        }
        .onLoad {
            let address = input.toAddress
            let addressItemsDescriptor = FetchDescriptor<AddressBookItem>(
                predicate: #Predicate { $0.address == address }
            )
            let addressItems = try? modelContext.fetch(addressItemsDescriptor)

            canShowAddressBook = addressItems?.isEmpty ?? false && !(appViewModel.selectedVault?.coins.map(\.address).contains(input.toAddress) ?? true)
        }
        .onChange(of: navigateToAddressBook) { _, shouldNavigate in
            if shouldNavigate {
                // Store address count before navigation
                let allAddressesDescriptor = FetchDescriptor<AddressBookItem>()
                addressCountBeforeNavigation = (try? modelContext.fetch(allAddressesDescriptor).count) ?? 0

                router.navigate(to: SettingsRoute.addAddressBook(
                    address: input.toAddress,
                    chain: .init(coinMeta: input.coin.toCoinMeta())
                ))
                navigateToAddressBook = false
            } else if addressCountBeforeNavigation > 0 {
                // Check if address was added when returning from navigation
                let allAddressesDescriptor = FetchDescriptor<AddressBookItem>()
                let currentCount = (try? modelContext.fetch(allAddressesDescriptor).count) ?? 0
                if currentCount > addressCountBeforeNavigation {
                    appViewModel.restart()
                    addressCountBeforeNavigation = 0
                }
            }
        }
    }

    var header: some View {
        SendCryptoDoneHeaderView(
            coin: input.coin,
            cryptoAmount: input.amountCrypto,
            fiatAmount: input.amountFiat.formatToFiat(includeCurrencySymbol: true)
        )
    }

    var summary: some View {
        VStack(spacing: 18) {
            Group {
                SendCryptoTransactionHashRowView(
                    hash: input.hash,
                    explorerLink: input.explorerLink,
                    showCopy: false,
                    showAlert: .constant(false)
                )
                separator
            }
            .showIf(input.hash.isNotEmpty)

            if let vaultName = appViewModel.selectedVault?.name, vaultName.isNotEmpty {
                SendCryptoTransactionDetailsRow(
                    title: "from",
                    description: vaultName,
                    bracketValue: input.fromAddress
                )
                separator
            }

            Group {
                SendCryptoTransactionDetailsRow(
                    title: "to",
                    description: input.toAddress
                ) {
                    addToAddressBookButton
                        .showIf(showAddressBookButton)
                }
                separator
            }
            .showIf(input.toAddress.isNotEmpty)

            Group {
                SendCryptoTransactionDetailsRow(
                    title: "memo",
                    description: input.memo
                )
                separator
            }
            .showIf(input.memo.isNotEmpty)

            SendCryptoTransactionDetailsRow(
                title: "network",
                description: input.coin.chain.name,
                icon: input.coin.chain.logo
            )

            separator

            SendCryptoTransactionDetailsRow(
                title: "estNetworkFee",
                description: input.fee.crypto,
                secondaryDescription: input.fee.fiat
            )
            Group {
                if let signDirect = input.keysignPayload?.signDirect {
                    separator
                    SignDirectDisplayView(signDirect: signDirect)
                } else if let signAmino = input.keysignPayload?.signAmino {
                    separator
                    SignAminoDisplayView(signAmino: signAmino)
                }
            }
        }
        .padding(24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    var separator: some View {
        Separator()
            .opacity(0.8)
    }

    var continueButton: some View {
        PrimaryButton(title: "done") {
            appViewModel.restart()
        }
    }

    var addToAddressBookButton: some View {
        Button {
            navigateToAddressBook = true
        } label: {
            HStack(spacing: 6) {
                Icon(named: "plus", color: Theme.colors.alertSuccess, size: 16)

                Text("addToAddressBook".localized)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 99).stroke(Theme.colors.alertSuccess, lineWidth: 0.5))
            .fixedSize()
        }
    }

    func openLink() {
        if let url = URL(string: input.explorerLink) {
            openURL(url)
        }
    }
}

#Preview("Without SignData") {
    SendCryptoSecondaryDoneView(
        input: .init(
            coin: .example,
            amountCrypto: "30 RUNE",
            amountFiat: "US$ 200",
            hash: "44B447A6A8BCABCCEC6E3EE9DE366EA4E0CDFC2C0BFB59D51E1A12D27B0C51AB",
            explorerLink: "https://thorchain.net/tx/44B447A6A8BCABCCEC6E3EE9DE366EA4E0CDFC2C0BFB59D51E1A12D27B0C51AB",
            memo: "test",
            isSend: true,
            fromAddress: "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z",
            toAddress: "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z",
            fee: FeeDisplay(crypto: "0.001 RUNE", fiat: "US$ 0.00"),
            keysignPayload: nil
        )
    ).environmentObject(AppViewModel())
}

#Preview("With SignDirect") {
    SendCryptoSecondaryDoneView(
        input: .init(
            coin: .example,
            amountCrypto: "30 RUNE",
            amountFiat: "US$ 200",
            hash: "78a50364c4bbd5c5df8407215a8161044ff07ac00a90fee5b1a7770f8291f0d1",
            explorerLink: "https://thorchain.net/tx/78a50364c4bbd5c5df8407215a8161044ff07ac00a90fee5b1a7770f8291f0d1",
            memo: "secure-:ltc1qc56q990vzj3a89d544dvj28grrpxqq0pw64hq4",
            isSend: true,
            fromAddress: "thor1zgmsl5g25mfrtyuyrgdxh7r35wyyreh3p89jgq",
            toAddress: "",
            fee: FeeDisplay(crypto: "0.02 RUNE", fiat: "US$ 0.10"),
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
        )
    ).environmentObject(AppViewModel())
}

#Preview("With SignAmino") {
    SendCryptoSecondaryDoneView(
        input: .init(
            coin: .example,
            amountCrypto: "0.006 ATOM",
            amountFiat: "US$ 0.05",
            hash: "235ed1789c6acd39f020c4b4ef80565bb154d97fb52fc8e76d3fa0253762c653",
            explorerLink: "https://www.mintscan.io/cosmos/tx/235ed1789c6acd39f020c4b4ef80565bb154d97fb52fc8e76d3fa0253762c653",
            memo: "",
            isSend: true,
            fromAddress: "cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas",
            toAddress: "cosmos1g9na87hc34r90spqdfeu3m2rxswkv7qhalylas",
            fee: FeeDisplay(crypto: "0.001 ATOM", fiat: "US$ 0.01"),
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
        )
    ).environmentObject(AppViewModel())
}
