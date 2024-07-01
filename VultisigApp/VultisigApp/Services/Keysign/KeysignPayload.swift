//
//  KeysignPayload.swift
//  VultisigApp
//

import Foundation
import BigInt
import VultisigCommonData

struct KeysignPayload: Codable, Hashable {
    let coin: CoinMeta
    let fromAddress: String
    let toAddress: String
    let toAmount: BigInt
    let chainSpecific: BlockChainSpecific
    let utxos: [UtxoInfo]
    let memo: String?
    let swapPayload: SwapPayload?
    let approvePayload: ERC20ApprovePayload?
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String

    var toAmountString: String {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -coin.decimals, significand: 1)
        return "\(decimalAmount * power) \(coin.ticker)"
    }

    static let example = KeysignPayload(coin: Coin.example.toCoinMeta(), fromAddress: "fromAddress", toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100, sendMaxAmount: false), utxos: [], memo: "Memo", swapPayload: nil, approvePayload: nil, vaultPubKeyECDSA: "12345", vaultLocalPartyID: "iPhone-100")
}

//extension KeysignPayload: ProtoMappable {
//
//    init(protobuff: VSKeysignPayload) {
//
//    }
//
//    func mapToProtobuff() -> VSKeysignPayload {
//
//    }
//}
