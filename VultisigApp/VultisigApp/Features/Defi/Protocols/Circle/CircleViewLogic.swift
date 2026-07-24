//
//  CircleViewLogic.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/12/25.
//

import OSLog
import SwiftUI
import BigInt
import WalletCore
import VultisigCommonData

private let logger = Logger(subsystem: "com.vultisig.app", category: "circle-view-logic")

// MARK: - Logic (Methods)
struct CircleViewLogic {

    struct CircleWithdrawalInfo {
        let usdcContract: String
    }

    func checkExistingWallet(vault: Vault) async throws -> String? {
        let (chain, _) = CircleViewLogic.getChainDetails()

        guard let ethCoin = vault.coins.first(where: { $0.chain == chain }) else {
            throw CircleServiceError.keysignError("No Ethereum found in vault. Please add Ethereum first.")
        }

        return try await CircleApiService.shared.fetchWallet(ethAddress: ethCoin.address)
    }

    func createWallet(vault: Vault) async throws -> String {
        let (chain, _) = CircleViewLogic.getChainDetails()

        guard let ethCoin = vault.coins.first(where: { $0.chain == chain }) else {
            throw CircleServiceError.keysignError("No ETH coin found in vault. Please add Ethereum first.")
        }

        return try await CircleApiService.shared.createWallet(ethAddress: ethCoin.address)
    }

    /// Fetches fresh balances from chain and upserts them into the vault's cached `CirclePosition`.
    @MainActor
    func refresh(vault: Vault) async throws -> (usdcBalance: Decimal, ethBalance: Decimal) {
        guard let mscaAddress = vault.circleWalletAddress else {
            return (.zero, .zero)
        }
        let (usdcBalance, ethBalance) = try await fetchData(address: mscaAddress, vault: vault)
        try CirclePositionStorageService().upsert(
            usdcBalance: usdcBalance,
            ethBalance: ethBalance,
            for: vault
        )
        return (usdcBalance, ethBalance)
    }

    /// Returns: (USDC Balance, ETH Balance)
    func fetchData(address: String, vault: Vault) async throws -> (Decimal, Decimal) {
        let (chain, usdcContract) = CircleViewLogic.getChainDetails()

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
            logger.error("Circle Fetch Error: \(error.localizedDescription)")
            throw error
        }
    }

    func getWithdrawalPayload(vault: Vault, recipient: String, amount: BigInt, isNative: Bool = false) async throws -> KeysignPayload {
        guard vault.circleWalletAddress != nil else {
            throw CircleServiceError.keysignError("Missing Circle Wallet Address")
        }

        let (chain, usdcContract) = CircleViewLogic.getChainDetails()

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

        let chainSpecific = BlockChainSpecific.Ethereum(
            maxFeePerGasWei: boostedGasPrice,
            priorityFeeWei: boostedPriorityFee,
            nonce: nonce,
            gasLimit: gasLimit
        )

        return try makeWithdrawalKeysignPayload(
            vault: vault,
            chain: chain,
            to: to,
            value: value,
            memoHex: dataHex,
            chainSpecific: chainSpecific
        )
    }

    /// Assembles the keysign payload for a Circle MSCA withdrawal.
    ///
    /// A withdrawal is a contract call to the MSCA — `execute(USDC, 0, transfer(vault, amount))`
    /// — whose calldata travels in `memo`. The EVM signer only forwards `memo` as `tx.data` on
    /// the native-coin path; an ERC-20 coin instead builds a plain `transfer(toAddress, toAmount)`
    /// and drops the memo, which with `toAmount == 0` signs a no-op. The payload coin must
    /// therefore be the chain's native coin, not the USDC token.
    func makeWithdrawalKeysignPayload(
        vault: Vault,
        chain: Chain,
        to: String,
        value: BigInt,
        memoHex: String,
        chainSpecific: BlockChainSpecific
    ) throws -> KeysignPayload {
        guard let coin = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
            throw CircleServiceError.keysignError("Missing native coin for \(chain.name)")
        }

        return KeysignPayload(
            coin: coin,
            toAddress: to,
            toAmount: value,
            chainSpecific: chainSpecific,
            utxos: [],
            memo: memoHex, // execute(...) calldata; only forwarded as tx.data on the native-coin path
            swapPayload: nil, // No swap payload = shows as Send
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20) == .DKLS ? "dkls" : "gg20",
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    static func getChainDetails() -> (chain: Chain, usdcContract: String) {
        return (.ethereum, CircleConstants.usdcMainnet)
    }

}
