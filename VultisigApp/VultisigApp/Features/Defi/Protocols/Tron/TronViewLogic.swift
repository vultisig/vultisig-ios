//
//  TronViewLogic.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI
import BigInt

// MARK: - Logic (Methods)
struct TronViewLogic {
    
    private let tronService: TronService
    
    /// Initialize with optional dependency injection for testing
    init(tronService: TronService = .shared) {
        self.tronService = tronService
    }
    
    /// Fetches account data including frozen balances and resources
    /// Returns: (availableBalance, frozenBandwidth, frozenEnergy, unfreezing, pendingWithdrawals, accountResource)
    func fetchData(vault: Vault) async throws -> (Decimal, Decimal, Decimal, Decimal, [TronPendingWithdrawal], TronAccountResourceResponse?) {
        guard let trxCoin = vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken }) else {
            throw TronStakingError.noTrxCoin
        }
        
        let address = trxCoin.address
        
        // Fetch account info and resources in parallel using shared service
        async let accountTask = tronService.getAccount(address: address)
        async let resourceTask = tronService.getAccountResource(address: address)
        
        let (account, resource) = try await (accountTask, resourceTask)
        
        // Calculate available balance (in TRX, not SUN)
        let balanceSun = account.balance ?? 0
        let availableBalance = Decimal(balanceSun) / Decimal(1_000_000)
        
        // Parse frozen balances from frozenV2 array (Stake 2.0)
        // Convert from SUN to TRX
        let frozenBandwidth = Decimal(account.frozenBandwidthSun) / Decimal(1_000_000)
        let frozenEnergy = Decimal(account.frozenEnergySun) / Decimal(1_000_000)
        
        // Parse unfreezing balance (pending withdrawal)
        let unfreezing = Decimal(account.unfreezingTotalSun) / Decimal(1_000_000)
        
        // Parse individual pending withdrawals
        let pendingWithdrawals: [TronPendingWithdrawal] = (account.unfrozenV2 ?? []).compactMap { entry in
            guard let amountSun = entry.unfreeze_amount, let expireTime = entry.unfreeze_expire_time else {
                return nil
            }
            let amountTrx = Decimal(amountSun) / Decimal(1_000_000)
            let expirationDate = Date(timeIntervalSince1970: TimeInterval(expireTime / 1000))
            return TronPendingWithdrawal(amount: amountTrx, expirationDate: expirationDate)
        }.sorted { $0.expirationDate < $1.expirationDate }
        
        return (availableBalance, frozenBandwidth, frozenEnergy, unfreezing, pendingWithdrawals, resource)
    }
    
    /// Gets the TRX coin from vault
    static func getTrxCoin(vault: Vault) -> Coin? {
        return vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken })
    }
    
    /// Gets the wallet TRX balance
    static func getWalletTrxBalance(vault: Vault) -> Decimal {
        if let trxCoin = vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken }) {
            return trxCoin.balanceDecimal
        }
        return .zero
    }
    
    /// Creates a freeze transaction payload
    func getFreezePayload(
        vault: Vault,
        amount: BigInt,
        resourceType: TronResourceType
    ) async throws -> KeysignPayload {
        guard let trxCoin = vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken }) else {
            throw TronStakingError.noTrxCoin
        }
        
        // Build memo first so fee calculation includes memo cost
        let memo = "FREEZE:\(resourceType.tronResourceString)"
        
        // Get block info with to address and memo for correct fee estimation
        let blockInfo = try await tronService.getBlockInfo(coin: trxCoin, to: trxCoin.address, memo: memo)
        
        guard case .Tron = blockInfo else {
            throw TronStakingError.invalidBlockInfo
        }
        
        let payload = KeysignPayload(
            coin: trxCoin,
            toAddress: trxCoin.address, // Freeze goes to self
            toAmount: amount,
            chainSpecific: blockInfo,
            utxos: [],
            memo: memo,
            swapPayload: nil,
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
        
        return payload
    }
    
    /// Creates an unfreeze transaction payload
    func getUnfreezePayload(
        vault: Vault,
        amount: BigInt,
        resourceType: TronResourceType
    ) async throws -> KeysignPayload {
        guard let trxCoin = vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken }) else {
            throw TronStakingError.noTrxCoin
        }
        
        // Build memo first so fee calculation includes memo cost
        let memo = "UNFREEZE:\(resourceType.tronResourceString)"
        
        // Get block info with to address and memo for correct fee estimation
        let blockInfo = try await tronService.getBlockInfo(coin: trxCoin, to: trxCoin.address, memo: memo)
        
        guard case .Tron = blockInfo else {
            throw TronStakingError.invalidBlockInfo
        }
        
        let payload = KeysignPayload(
            coin: trxCoin,
            toAddress: trxCoin.address, // Unfreeze returns to self
            toAmount: amount,
            chainSpecific: blockInfo,
            utxos: [],
            memo: memo,
            swapPayload: nil,
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
        
        return payload
    }
}

// MARK: - Errors

enum TronStakingError: LocalizedError {
    case noTrxCoin
    case invalidBlockInfo
    case freezeFailed(String)
    case unfreezeFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noTrxCoin:
            return NSLocalizedString("tronErrorNoTrxCoin", comment: "No TRX coin found in vault")
        case .invalidBlockInfo:
            return NSLocalizedString("tronErrorInvalidBlockInfo", comment: "Invalid block info")
        case .freezeFailed(let message):
            return String(format: NSLocalizedString("tronErrorFreezeFailed", comment: "Freeze failed: %@"), message)
        case .unfreezeFailed(let message):
            return String(format: NSLocalizedString("tronErrorUnfreezeFailed", comment: "Unfreeze failed: %@"), message)
        }
    }
}
