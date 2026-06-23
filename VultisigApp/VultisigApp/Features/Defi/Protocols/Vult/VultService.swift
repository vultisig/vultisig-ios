//
//  VultService.swift
//  VultisigApp
//

import Foundation
import BigInt
import WalletCore

enum VultServiceError: Error {
    case invalidAddress(String)
    case missingCoin(String)
    case keysignError(String)
    case readError(String)
}

extension VultServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidAddress(let value):
            return "Invalid address: \(value)"
        case .missingCoin(let message):
            return message
        case .keysignError(let message):
            return message
        case .readError(let message):
            return message
        }
    }
}

/// Pure ABI/calldata encoder for the sVULT staking wrapper.
///
/// All calls are direct EOA calls to the wrapper (`to = stakedVult, value = 0,
/// data = calldata`). Each encoder is byte-equal to a fixed golden vector
/// (`VultServiceTests`): selector + head-only static-arg layout.
struct VultService {
    static let shared = VultService()

    private init() {}

    // MARK: - Calldata encoders (byte-match golden vectors)

    /// `depositFor(address account, uint256 value)` — selector `0x2f4f21e2`. Stake:
    /// pulls VULT via `transferFrom` and mints sVULT 1:1 to `account`.
    func encodeDepositFor(account: String, amount: BigInt) throws -> Data {
        let accountData = try addressData(account)
        let fn = EthereumAbiFunction(name: "depositFor")
        fn.addParamAddress(val: accountData, isOutput: false)
        fn.addParamUInt256(val: amount.serializeForEvm(), isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    /// `requestUnstake(uint256 amount)` — selector `0x23095721`. Burns sVULT from
    /// the active balance into escrow and starts the cooldown; returns a `requestId`.
    func encodeRequestUnstake(amount: BigInt) throws -> Data {
        let fn = EthereumAbiFunction(name: "requestUnstake")
        fn.addParamUInt256(val: amount.serializeForEvm(), isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    /// `claim(uint256 requestId, address receiver)` — selector `0xddd5e1b2`. After
    /// maturity, returns the unstaked VULT to `receiver`.
    func encodeClaim(requestId: BigInt, receiver: String) throws -> Data {
        let receiverData = try addressData(receiver)
        let fn = EthereumAbiFunction(name: "claim")
        fn.addParamUInt256(val: requestId.serializeForEvm(), isOutput: false)
        fn.addParamAddress(val: receiverData, isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    /// `cancelUnstake(uint256 requestId)` — selector `0x2b187b2b`. Restores the
    /// escrowed sVULT to the active balance.
    func encodeCancelUnstake(requestId: BigInt) throws -> Data {
        let fn = EthereumAbiFunction(name: "cancelUnstake")
        fn.addParamUInt256(val: requestId.serializeForEvm(), isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    /// `approve(address spender, uint256 amount)` on VULT, spender = the sVULT
    /// wrapper — selector `0x095ea7b3`. Used by the stake approve-bundle.
    func encodeApprove(amount: BigInt) throws -> Data {
        let spenderData = try addressData(VultConstants.stakedVult)
        let fn = EthereumAbiFunction(name: "approve")
        fn.addParamAddress(val: spenderData, isOutput: false)
        fn.addParamUInt256(val: amount.serializeForEvm(), isOutput: false)
        return EthereumAbi.encode(fn: fn)
    }

    // MARK: - Helpers

    private func addressData(_ address: String) throws -> Data {
        guard let any = AnyAddress(string: address, coin: .ethereum) else {
            throw VultServiceError.invalidAddress(address)
        }
        return any.data
    }
}
