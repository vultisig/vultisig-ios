//
//  HyperliquidCctpDeposit.swift
//  VultisigApp
//
//  Deposit route: CCTP from Arbitrum straight into the TRADING
//  account on HyperCore (Circle, "Transfer USDC from Arbitrum to HyperCore").
//  Bridge2 is not used: it credits the sender, which is the main address.
//
//  Two vault signatures, both on the main Arbitrum address:
//    1. EIP-3009 `ReceiveWithAuthorization` on native USDC, letting
//       `CctpExtension` pull the amount (typed data, the existing keysign path).
//    2. The Arbitrum tx `CctpExtension.batchDepositForBurnWithAuth(auth, burn)`
//       with mintRecipient = destinationCaller = `CctpForwarder` (HyperEVM),
//       domain 19, maxFee 0.20 USDC, minFinality 1000, and the forwarder
//       hookData naming the trading address. The existing send flow cannot
//       carry this calldata yet; its encoding lands with live deposits.
//

import Foundation

enum HLCctp {
    static let arbitrumChainId: UInt64 = 42_161
    static let arbitrumUsdc = "0xaf88d065e77c8cc2239327c5edb3a432268e5831"
    static let cctpExtensionArbitrum = "0xa95d9c1f655341597c94393fddc30cf3c08e4fce"
    /// On HyperEVM. Must be BOTH mintRecipient and destinationCaller, or funds are stuck.
    static let cctpForwarderHyperEvm = "0xb21d281dedb17ae5b501f6aa8256fe38c4e45757"
    static let hyperEvmDomain: UInt32 = 19
    static let forwardingFee: Decimal = Decimal(string: "0.2") ?? 0
    static let fastFinalityThreshold: UInt32 = 1000
    /// One-time fee on a new HyperCore account.
    static let activationFee: Decimal = 1

    enum DestinationDex: UInt32 {
        case perps = 0
        case spot = 0xFFFF_FFFF
    }

    /// `cctp-forward` magic (24 bytes, zero padded) ‖ version u32 ‖ dataLength u32
    /// ‖ recipient (20) ‖ destinationDex u32. All big-endian.
    static func forwardHookData(recipient: String, dex: DestinationDex = .perps) throws -> Data {
        var data = Data("cctp-forward".utf8)
        data.append(Data(count: 24 - data.count))
        HLMsgPack.appendBigEndian(UInt32(0), into: &data)
        HLMsgPack.appendBigEndian(UInt32(24), into: &data)
        data.append(try HLAddress.bytes(recipient))
        HLMsgPack.appendBigEndian(dex.rawValue, into: &data)
        return data
    }

    static func usdcUnits(_ amount: Decimal) -> UInt64 {
        var scaled = amount * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }
}

struct HLCctpDeposit: Equatable, Sendable {
    let from: String
    let tradingAddress: String
    let amount: Decimal
    let hookData: Data
    let authorization: HLTypedData

    /// What lands in the trading account's perps balance.
    var credited: Decimal { amount - HLCctp.forwardingFee }

    static func make(from: String, tradingAddress: String, amount: Decimal, validBefore: UInt64, authNonce: Data) throws -> HLCctpDeposit {
        guard authNonce.count == 32 else { throw HLSigningError.invalidAddress("authNonce") }
        let authorization = HLTypedData(
            domain: HLTypedDomain(name: "USD Coin", version: "2", chainId: HLCctp.arbitrumChainId,
                                  verifyingContract: try HLAddress.bytes(HLCctp.arbitrumUsdc)),
            primaryType: "ReceiveWithAuthorization",
            fields: [
                HLTypedField(name: "from", value: .address(try HLAddress.bytes(from))),
                HLTypedField(name: "to", value: .address(try HLAddress.bytes(HLCctp.cctpExtensionArbitrum))),
                HLTypedField(name: "value", value: .uint256(HLCctp.usdcUnits(amount))),
                HLTypedField(name: "validAfter", value: .uint256(0)),
                HLTypedField(name: "validBefore", value: .uint256(validBefore)),
                HLTypedField(name: "nonce", value: .bytes32(authNonce))
            ]
        )
        return HLCctpDeposit(from: from.lowercased(), tradingAddress: tradingAddress.lowercased(), amount: amount,
                             hookData: try HLCctp.forwardHookData(recipient: tradingAddress), authorization: authorization)
    }
}
