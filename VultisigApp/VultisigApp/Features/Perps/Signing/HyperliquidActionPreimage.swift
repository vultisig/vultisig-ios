//
//  HyperliquidActionPreimage.swift
//  VultisigApp
//
//  What a co-signer needs to rebuild a Hyperliquid digest and show what it
//  signs. Mirrors the proposed commondata message
//  `HyperliquidActionPreimage` (`CustomMessagePayload.hyperliquid = 8`):
//  display and verification only, it never feeds `keysignMessages`.
//
//  The action travels as msgpack bytes, not JSON: `connectionId` hashes
//  msgpack with ordered maps, so the bytes are the ground truth.
//  User-signed actions carry no bytes; their EIP-712 is already readable.
//

import Foundation

struct HyperliquidActionPreimage: Codable, Hashable, Sendable {
    /// The action's `type`: "order", "cancel", "modify", "batchModify",
    /// "updateLeverage", "updateIsolatedMargin", "noop", "withdraw3",
    /// "approveAgent", "approveBuilderFee".
    let kind: String
    /// L1: the exact bytes hashed into `connectionId`. User-signed: empty.
    let actionMsgpack: Data
    let nonce: UInt64
    /// Always nil in v1 (no subaccounts).
    var vaultAddress: String?
    var expiresAfter: UInt64?
    let isMainnet: Bool

    init(kind: String, actionMsgpack: Data, nonce: UInt64, vaultAddress: String? = nil, expiresAfter: UInt64? = nil, isMainnet: Bool) {
        self.kind = kind
        self.actionMsgpack = actionMsgpack
        self.nonce = nonce
        self.vaultAddress = vaultAddress
        self.expiresAfter = expiresAfter
        self.isMainnet = isMainnet
    }

    init(_ request: PerpsSignRequest) throws {
        switch request {
        case let .l1(action, nonce, isMainnet, vaultAddress, expiresAfter):
            self.init(kind: Self.type(of: action), actionMsgpack: try HLMsgPack.encode(action), nonce: nonce,
                      vaultAddress: vaultAddress, expiresAfter: expiresAfter, isMainnet: isMainnet)
        case .userSigned(let signed):
            self.init(kind: Self.type(of: signed.action), actionMsgpack: Data(), nonce: signed.nonce,
                      isMainnet: signed.action["hyperliquidChain"] == .string("Mainnet"))
        }
    }

    private static func type(of action: HLValue) -> String {
        if case .string(let type)? = action["type"] { return type }
        return ""
    }
}
