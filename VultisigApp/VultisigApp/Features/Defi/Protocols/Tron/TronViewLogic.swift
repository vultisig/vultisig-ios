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
    
    private let tronService = TronService.shared
    private let tronAPIService = TronAPIService(httpClient: HTTPClient())
    
    /// Fetches account data including frozen balances and resources
    /// Returns: (availableBalance, frozenBandwidth, frozenEnergy, accountResource)
    func fetchData(vault: Vault) async throws -> (Decimal, Decimal, Decimal, TronAccountResourceResponse?) {
        guard let trxCoin = vault.coins.first(where: { $0.chain == .tron && $0.isNativeToken }) else {
            throw TronStakingError.noTrxCoin
        }
        
        let address = trxCoin.address
        
        // Fetch account info and resources in parallel using shared service
        async let accountTask = tronAPIService.getAccount(address: address)
        async let resourceTask = tronAPIService.getAccountResource(address: address)
        
        let (account, resource) = try await (accountTask, resourceTask)
        
        // Calculate available balance (in TRX, not SUN)
        let balanceSun = account.balance ?? 0
        let availableBalance = Decimal(balanceSun) / Decimal(1_000_000)
        
        // Parse frozen balances from frozenV2 array (Stake 2.0)
        // Convert from SUN to TRX
        let frozenBandwidth = Decimal(account.frozenBandwidthSun) / Decimal(1_000_000)
        let frozenEnergy = Decimal(account.frozenEnergySun) / Decimal(1_000_000)
        
        return (availableBalance, frozenBandwidth, frozenEnergy, resource)
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
        
        let blockInfo = try await tronService.getBlockInfo(coin: trxCoin)
        
        guard case let .Tron(timestamp, expiration, blockHeaderTimestamp, blockHeaderNumber, blockHeaderVersion, blockHeaderTxTrieRoot, blockHeaderParentHash, blockHeaderWitnessAddress, gasFeeEstimation) = blockInfo else {
            throw TronStakingError.invalidBlockInfo
        }
        
        let chainSpecific = BlockChainSpecific.Tron(
            timestamp: timestamp,
            expiration: expiration,
            blockHeaderTimestamp: blockHeaderTimestamp,
            blockHeaderNumber: blockHeaderNumber,
            blockHeaderVersion: blockHeaderVersion,
            blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
            blockHeaderParentHash: blockHeaderParentHash,
            blockHeaderWitnessAddress: blockHeaderWitnessAddress,
            gasFeeEstimation: gasFeeEstimation
        )
        
        // Use memo to encode freeze operation - TronHelper will parse it
        let memo = "FREEZE:\(resourceType.tronResourceString)"
        
        let payload = KeysignPayload(
            coin: trxCoin,
            toAddress: trxCoin.address, // Freeze goes to self
            toAmount: amount,
            chainSpecific: chainSpecific,
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
        
        let blockInfo = try await tronService.getBlockInfo(coin: trxCoin)
        
        guard case let .Tron(timestamp, expiration, blockHeaderTimestamp, blockHeaderNumber, blockHeaderVersion, blockHeaderTxTrieRoot, blockHeaderParentHash, blockHeaderWitnessAddress, gasFeeEstimation) = blockInfo else {
            throw TronStakingError.invalidBlockInfo
        }
        
        let chainSpecific = BlockChainSpecific.Tron(
            timestamp: timestamp,
            expiration: expiration,
            blockHeaderTimestamp: blockHeaderTimestamp,
            blockHeaderNumber: blockHeaderNumber,
            blockHeaderVersion: blockHeaderVersion,
            blockHeaderTxTrieRoot: blockHeaderTxTrieRoot,
            blockHeaderParentHash: blockHeaderParentHash,
            blockHeaderWitnessAddress: blockHeaderWitnessAddress,
            gasFeeEstimation: gasFeeEstimation
        )
        
        // Use memo to encode unfreeze operation - TronHelper will parse it
        let memo = "UNFREEZE:\(resourceType.tronResourceString)"
        
        let payload = KeysignPayload(
            coin: trxCoin,
            toAddress: trxCoin.address, // Unfreeze returns to self
            toAmount: amount,
            chainSpecific: chainSpecific,
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
