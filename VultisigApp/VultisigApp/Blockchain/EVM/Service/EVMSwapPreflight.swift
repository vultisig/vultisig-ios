//
//  EVMSwapPreflight.swift
//  VultisigApp
//
//  Rejects already-reverting EVM aggregator calldata before an MPC ceremony
//  starts. Every participating device runs this from KeysignViewModel.
//

import BigInt
import Foundation

protocol EVMSwapPreflightChecking {
    func validate(_ payload: KeysignPayload, localCoinAddress: String?) async throws
}

struct EVMSwapPreflightCall: Equatable {
    let chain: Chain
    let from: String
    let to: String
    let data: String
    let valueHex: String
}

enum EVMSwapPreflightError: LocalizedError, Equatable {
    case reverted(detail: String)

    var errorDescription: String? {
        switch self {
        case .reverted:
            return SwapError.slippageToleranceTooTight.localizedDescription
        }
    }

    static func isExecutionRevert(code: Int, message: String) -> Bool {
        if code == 3 { return true }
        let message = message.lowercased()
        let abiPayload = message.dropFirst(2)
        if message == "0x" ||
            (message.hasPrefix("0x") && abiPayload.count >= 8 && abiPayload.allSatisfy(\.isHexDigit)) {
            return true
        }
        let markers = [
            "revert",
            "vm execution",
            "execution failed",
            "insufficient output",
            "return amount is not enough"
        ]
        return markers.contains { message.contains($0) }
    }
}

struct EVMSwapPreflight: EVMSwapPreflightChecking {
    typealias Simulator = (EVMSwapPreflightCall) async throws -> Void

    private let simulator: Simulator

    init(simulator: @escaping Simulator = Self.simulate) {
        self.simulator = simulator
    }

    func validate(_ payload: KeysignPayload, localCoinAddress: String?) async throws {
        guard let call = try Self.call(for: payload, localCoinAddress: localCoinAddress) else { return }
        try await simulator(call)
    }

    static func call(for payload: KeysignPayload, localCoinAddress: String?) throws -> EVMSwapPreflightCall? {
        guard payload.coin.chainType == .EVM,
              // A router call against current state may fail only because this
              // approval has not been mined yet. Ordinary eth_call cannot
              // simulate the two transactions atomically, so keep that flow on
              // its existing approval-first path instead of false-blocking it.
              payload.approvePayload == nil,
              case let .generic(swap)? = payload.swapPayload,
              requiresPreflight(swap.provider) else {
            return nil
        }

        let transaction = swap.quote.tx
        guard let localCoinAddress,
              swap.fromCoin.chain == payload.coin.chain,
              SwapRecipientVerifier.addressesMatch(localCoinAddress, payload.coin.address),
              transaction.from.isEmpty || SwapRecipientVerifier.addressesMatch(transaction.from, localCoinAddress),
              !transaction.to.isEmpty,
              !transaction.data.isEmpty,
              let value = BigInt(transaction.value),
              value >= 0 else {
            throw SwapError.routeUnavailable
        }

        return EVMSwapPreflightCall(
            chain: payload.coin.chain,
            from: localCoinAddress,
            to: transaction.to,
            data: transaction.data,
            valueHex: "0x" + String(value.magnitude, radix: 16)
        )
    }

    private static func requiresPreflight(_ provider: SwapProviderId) -> Bool {
        switch provider {
        case .oneInch, .kyberSwap, .lifi:
            return true
        case .swapkit, .jupiter, .unknown:
            return false
        }
    }

    private static func simulate(_ call: EVMSwapPreflightCall) async throws {
        let service = try EvmService.getService(forChain: call.chain)
        try await withTimeout(seconds: 15) {
            try await service.simulateSwap(call)
        }
    }
}
