//
//  CircleViewLogic.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/12/25.
//

import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

// MARK: - Logic (Methods)
struct CircleViewLogic {

    struct CircleWithdrawalInfo {
        let usdcContract: String
    }

    func checkExistingWallet(vault: Vault) async throws -> String? {
        let (chain, _) = CircleViewLogic.getChainDetails(vault: vault)

        guard let ethCoin = vault.coins.first(where: { $0.chain == chain }) else {
            throw CircleServiceError.keysignError("No Ethereum found in vault. Please add Ethereum first.")
        }

        return try await CircleApiService.shared.fetchWallet(ethAddress: ethCoin.address)
    }

    func createWallet(vault: Vault) async throws -> String {
        let (chain, _) = CircleViewLogic.getChainDetails(vault: vault)

        guard let ethCoin = vault.coins.first(where: { $0.chain == chain }) else {
            throw CircleServiceError.keysignError("No ETH coin found in vault. Please add Ethereum first.")
        }

        return try await CircleApiService.shared.createWallet(ethAddress: ethCoin.address)
    }

    /// Returns: (USDC Balance, ETH Balance)
    func fetchData(address: String, vault: Vault) async throws -> (Decimal, Decimal) {
        let (chain, usdcContract) = CircleViewLogic.getChainDetails(vault: vault)

        do {
            let service = try EvmService.getService(forChain: chain)

            guard let nativeCoin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
                return (.zero, .zero)
            }

            async let usdcBalanceBigInt = service.fetchERC20TokenBalance(contractAddress: usdcContract, walletAddress: address)
            async let ethBalanceString = service.getBalance(coin: nativeCoin.toCoinMeta(), address: address)

            let (usdcVal, ethValStr) = try await (usdcBalanceBigInt, ethBalanceString)
            let ethVal = BigInt(ethValStr) ?? 0

            let usdcBalance = (Decimal(string: String(usdcVal)) ?? 0) / pow(10, 6)
            let ethBalance = (Decimal(string: String(ethVal)) ?? 0) / pow(10, 18)

            return (usdcBalance, ethBalance)

        } catch {
            print("Circle Fetch Error: \(error.localizedDescription)")
            throw error
        }
    }

    func getWithdrawalPayload(vault: Vault, recipient: String, amount: BigInt, isNative: Bool = false) async throws -> KeysignPayload {
        guard vault.circleWalletAddress != nil else {
            throw CircleServiceError.keysignError("Missing Circle Wallet Address")
        }

        let (chain, usdcContract) = CircleViewLogic.getChainDetails(vault: vault)

        let withdrawalInfo = CircleWithdrawalInfo(usdcContract: usdcContract)

        let (to, value, data) = try CircleService.shared.getWithdrawalValues(
            vault: vault,
            recipientAddress: recipient,
            amount: amount,
            info: withdrawalInfo,
            isNative: isNative
        )

        let service = try EvmService.getService(forChain: chain)

        let senderAddress = vault.coins.first(where: { $0.chain == chain })?.address ?? ""
        if senderAddress.isEmpty {
            throw CircleServiceError.keysignError("Missing ETH Address for \(chain.name)")
        }

        // Use FAST fee mode for Circle withdrawals
        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: senderAddress, mode: .fast)

        // Apply boost for faster confirmation
        let minMaxFee = BigInt(2_000_000_000) // 2 Gwei minimum
        let boostedGasPrice = max(gasPrice * 2, minMaxFee)

        // Priority fee must be <= max fee
        let desiredPriorityFee = max(priorityFee * 2, BigInt(100_000_000)) // At least 0.1 Gwei
        let boostedPriorityFee = min(desiredPriorityFee, boostedGasPrice)

        var dataHex = data.hexString
        if !dataHex.hasPrefix("0x") {
            dataHex = "0x" + dataHex
        }

        // Verify Circle Wallet is deployed
        let code = try await service.getCode(address: to)
        let isDeployed = code != "0x" && code.count > 2

        if !isDeployed {
            throw CircleServiceError.walletNotDeployed
        }

        // Estimate Gas
        let gasLimit = try await service.estimateGasLimitForSwap(
            senderAddress: senderAddress,
            toAddress: to,
            value: value,
            data: dataHex
        )

        guard let coin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
            throw CircleServiceError.keysignError("Missing ETH Coin")
        }

        let chainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: boostedGasPrice,
            priorityFeeWei: boostedPriorityFee,
            nonce: nonce,
            gasLimit: gasLimit
        )

        let payloadWithData = KeysignPayload(
            coin: coin,
            toAddress: to,
            toAmount: value,
            chainSpecific: chainSpecific,
            utxos: [],
            memo: dataHex, // Pass contract data as hex memo
            swapPayload: nil, // No swap payload = shows as Send
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20) == .DKLS ? "dkls" : "gg20",
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )

        return payloadWithData
    }

    static func getChainDetails(vault: Vault) -> (chain: Chain, usdcContract: String) {
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        let usdcContract = isSepolia ? CircleConstants.usdcSepolia : CircleConstants.usdcMainnet
        return (chain, usdcContract)
    }

    static func getWalletUSDCBalance(vault: Vault) -> Decimal {
        let (chain, _) = getChainDetails(vault: vault)
        if let usdcCoin = vault.coins.first(where: { $0.chain == chain && $0.ticker == "USDC" }) {
            return usdcCoin.balanceDecimal
        }
        return .zero
    }
}
