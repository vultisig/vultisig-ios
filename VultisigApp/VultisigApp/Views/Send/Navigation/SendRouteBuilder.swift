//
//  SendRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI
import VultisigCommonData

struct SendTransactionStruct: Hashable {
    let coin: Coin
    let amount: String
    let memo: String
    let toAddress: String
    let fromAddress: String
    let isFastVault: Bool
    let fastVaultPassword: String
    let transactionType: VSTransactionType
    
    init(coin: Coin, amount: String, memo: String, toAddress: String, fromAddress: String, isFastVault: Bool, fastVaultPassword: String, transactionType: VSTransactionType) {
        self.coin = coin
        self.amount = amount
        self.memo = memo
        self.toAddress = toAddress
        self.fromAddress = fromAddress
        self.isFastVault = isFastVault
        self.fastVaultPassword = fastVaultPassword
        self.transactionType = transactionType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(coin)
        hasher.combine(amount)
        hasher.combine(memo)
        hasher.combine(toAddress)
        hasher.combine(fromAddress)
        hasher.combine(isFastVault)
        hasher.combine(fastVaultPassword)
        hasher.combine(transactionType)
    }
    
    static func == (lhs: SendTransactionStruct, rhs: SendTransactionStruct) -> Bool {
        return lhs.coin == rhs.coin &&
            lhs.amount == rhs.amount &&
            lhs.memo == rhs.memo &&
            lhs.toAddress == rhs.toAddress &&
            lhs.fromAddress == rhs.fromAddress &&
            lhs.isFastVault == rhs.isFastVault &&
            lhs.fastVaultPassword == rhs.fastVaultPassword &&
            lhs.transactionType == rhs.transactionType
    }
}

struct SendRouteBuilder {
    
    @ViewBuilder
    func buildDetailsScreen(
        coin: Coin?,
        hasPreselectedCoin: Bool,
        tx: SendTransaction,
        vault: Vault
    ) -> some View {
        SendDetailsScreen(
            coin: coin,
            tx: tx,
            sendDetailsViewModel: SendDetailsViewModel(hasPreselectedCoin: hasPreselectedCoin),
            vault: vault
        )
    }
    
    @ViewBuilder
    func buildVerifyScreen(txData: SendTransactionStruct, tx: SendTransaction, vault: Vault) -> some View {
        SendVerifyScreen(txData: txData, tx: tx, vault: vault)
    }
    
    @ViewBuilder
    func buildPairScreen(
        vault: Vault,
        tx: SendTransaction,
        keysignPayload: KeysignPayload,
        fastVaultPassword: String?
    ) -> some View {
        SendPairScreen(
            vault: vault,
            tx: tx,
            keysignPayload: keysignPayload,
            fastVaultPassword: fastVaultPassword
        )
    }
    
    @ViewBuilder
    func buildKeysignScreen(input: KeysignInput, tx: SendTransaction) -> some View {
        SendKeysignScreen(input: input, tx: tx)
    }
    
    @ViewBuilder
    func buildDoneScreen(
        vault: Vault,
        hash: String,
        chain: Chain,
        tx: SendTransaction
    ) -> some View {
        SendDoneScreen(vault: vault, hash: hash, chain: chain, tx: tx)
    }
    
    @ViewBuilder
    func buildBuyScreen(address: String, blockChainCode: String, coinType: String) -> some View {
        BanxaDisclaimer(url:getBuyURL(address:address, blockChainCode: blockChainCode, coinType: coinType))
    }
    
    func getBuyURL(address: String, blockChainCode: String, coinType: String) -> URL {
        var components = URLComponents(string: "https://vultisig.banxa.com/")!
        components.queryItems = [
            URLQueryItem(name: "walletAddress", value: address),
            URLQueryItem(name: "blockchain", value: blockChainCode),
            URLQueryItem(name: "coinType", value: coinType),
        ]
        return components.url!
    }
    
}
