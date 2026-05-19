//
//  TonOpcode.swift
//  VultisigApp
//

import Foundation

/// TON internal-message body opcodes for the operations Vultisig surfaces in
/// keysign verify/done screens. The opcode is encoded as the first 32 bits of
/// the message body cell.
///
/// Sources:
///  - Jetton transfer: TEP-74 (https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md)
///  - NFT transfer:    TEP-62 (https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md)
///  - Excesses:        TEP-74 (return-of-gas notification)
///  - STON.fi v2 swap: https://docs.ston.fi/developer-section/api-reference-v2/ops
///  - DeDust swaps:    https://docs.tact-lang.org/cookbook/dexes/dedust/
enum TonOpcode {
    static let jettonTransfer: UInt32 = 0x0f8a7ea5
    static let nftTransfer: UInt32 = 0x5fcc3d14
    static let excesses: UInt32 = 0xd53276db
    static let ptonTransfer: UInt32 = 0x01f3835d
    static let stonfiV2Swap: UInt32 = 0x6664de2a
    static let dedustNativeSwap: UInt32 = 0xea06185d
    static let dedustJettonSwap: UInt32 = 0xe3a0d482
}
