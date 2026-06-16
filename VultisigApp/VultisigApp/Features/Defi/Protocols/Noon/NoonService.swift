//
//  NoonService.swift
//  VultisigApp
//

import Foundation
import BigInt
import WalletCore

enum NoonServiceError: Error {
    case invalidAddress(String)
    case belowMinimum(label: String, minimum: String)
    case missingCoin(String)
    case keysignError(String)
}

extension NoonServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidAddress(let value):
            return "Invalid address: \(value)"
        case .belowMinimum(let label, let minimum):
            return "\(label) must be at least \(minimum)"
        case .missingCoin(let message):
            return message
        case .keysignError(let message):
            return message
        }
    }
}

/// Pure ABI/calldata encoder for the Noon ERC-7540 vault.
///
/// All calls are direct EOA calls to the vault (no MSCA `execute()` wrapper —
/// that is a Circle-only concern). Calldata is byte-equal to the merged SDK
/// golden vectors (`packages/core/chain/chains/evm/noon/noon.test.ts`).
struct NoonService {
    static let shared = NoonService()

    private init() {}

    // MARK: - Calldata encoders (byte-match SDK golden vectors)

    /// `deposit(uint256 assets, address receiver)` — selector `0x6e553f65`.
    func encodeDeposit(assets: BigInt, receiver: String) throws -> Data {
        let receiverData = try addressData(receiver)
        let fn = EthereumAbiFunction(name: "deposit")
        fn.addParamUInt256(val: assets.serializeForEvm(), isOutput: false)
        fn.addParamAddress(val: receiverData, isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    /// `requestRedeem(uint256 shares, address receiver, address owner)` —
    /// selector `0x7d41c86e`.
    func encodeRequestRedeem(shares: BigInt, receiver: String, owner: String) throws -> Data {
        let receiverData = try addressData(receiver)
        let ownerData = try addressData(owner)
        let fn = EthereumAbiFunction(name: "requestRedeem")
        fn.addParamUInt256(val: shares.serializeForEvm(), isOutput: false)
        fn.addParamAddress(val: receiverData, isOutput: false)
        fn.addParamAddress(val: ownerData, isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    /// `withdraw(uint256 assets, address receiver, address owner)` — selector
    /// `0xb460af94`. Serves both instant withdraw and the post-settlement claim.
    func encodeWithdraw(assets: BigInt, receiver: String, owner: String) throws -> Data {
        let receiverData = try addressData(receiver)
        let ownerData = try addressData(owner)
        let fn = EthereumAbiFunction(name: "withdraw")
        fn.addParamUInt256(val: assets.serializeForEvm(), isOutput: false)
        fn.addParamAddress(val: receiverData, isOutput: false)
        fn.addParamAddress(val: ownerData, isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    /// `approve(address spender, uint256 amount)` on USDC, spender = the vault —
    /// selector `0x095ea7b3`.
    func encodeUsdcApprove(amount: BigInt) throws -> Data {
        let spenderData = try addressData(NoonConstants.vaultAddress)
        let fn = EthereumAbiFunction(name: "approve")
        fn.addParamAddress(val: spenderData, isOutput: false)
        fn.addParamUInt256(val: amount.serializeForEvm(), isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    // MARK: - Minimum guards

    func assertDepositMinimum(assets: BigInt, minimum: BigInt) throws {
        guard assets >= minimum else {
            throw NoonServiceError.belowMinimum(label: "Noon deposit assets", minimum: minimum.description)
        }
    }

    func assertRedeemMinimum(shares: BigInt, minimum: BigInt) throws {
        guard shares >= minimum else {
            throw NoonServiceError.belowMinimum(label: "Noon redeem shares", minimum: minimum.description)
        }
    }

    // MARK: - Helpers

    private func addressData(_ address: String) throws -> Data {
        guard let any = AnyAddress(string: address, coin: .ethereum) else {
            throw NoonServiceError.invalidAddress(address)
        }
        return any.data
    }
}
