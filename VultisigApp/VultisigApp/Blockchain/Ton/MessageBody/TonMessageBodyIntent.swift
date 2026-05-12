//
//  TonMessageBodyIntent.swift
//  VultisigApp
//

import Foundation

/// Decoded intent extracted from a TON internal-message body BOC.
///
/// Mirrors `TonMessageBodyIntent` in the Vultisig SDK. Addresses are
/// user-friendly bounceable strings (`EQ.../UQ...`) so they render directly in
/// the keysign UI without further conversion. Coin amounts are returned as
/// decimal strings because jetton supplies can exceed `UInt64`.
enum TonMessageBodyIntent: Equatable {
    case jettonTransfer(JettonTransfer)
    case nftTransfer(NftTransfer)
    case excesses(queryId: String)
    case swap(Swap)

    struct JettonTransfer: Equatable {
        let queryId: String
        /// Jetton units the sender is moving (in jetton's own decimals).
        let amount: String
        /// Real recipient of the jettons (NOT the jetton wallet contract).
        let destination: String
        /// Where excess TON gas is refunded to. May be nil.
        let responseDestination: String?
        /// TON forwarded with the inner notification to the recipient's jetton wallet.
        let forwardTonAmount: String
    }

    struct NftTransfer: Equatable {
        let queryId: String
        /// Address that receives ownership of the NFT.
        let newOwner: String
        /// Where excess TON gas is refunded to. May be nil.
        let responseDestination: String?
        /// TON forwarded with the ownership-change notification.
        let forwardAmount: String
    }

    struct Swap: Equatable {
        enum Provider: String, Equatable {
            case stonfi
            case dedust
        }

        enum OfferAsset: String, Equatable {
            case ton
            case jetton
        }

        let provider: Provider
        /// Asset being offered by the signed message.
        let offerAsset: OfferAsset
        /// Offered amount in the source asset's base units (decimal string).
        let offerAmount: String
        /// Minimum output encoded in the swap payload, when the protocol exposes it.
        let minOut: String?
        /// Final recipient, when encoded by the swap protocol.
        let receiverAddress: String?
        /// Refund target, when encoded by the swap protocol.
        let refundAddress: String?
        /// Excess gas target, when encoded by the swap protocol.
        let excessesAddress: String?
        /// Protocol-side pool/token wallet that identifies the swap route.
        let targetAddress: String?
    }
}
