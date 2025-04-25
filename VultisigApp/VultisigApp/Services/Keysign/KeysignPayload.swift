//
//  KeysignPayload.swift
//  VultisigApp
//

import Foundation
import BigInt

struct KeysignPayload: Codable, Hashable {
    let coin: Coin
    let toAddress: String
    let toAmount: BigInt
    let chainSpecific: BlockChainSpecific
    let utxos: [UtxoInfo]
    let memo: String?
    let swapPayload: SwapPayload?
    let approvePayload: ERC20ApprovePayload?
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String
    
    var fromAmountString: String {
        let decimalAmount = Decimal(string: swapPayload?.fromAmount.description ?? "") ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -(swapPayload?.fromCoin.decimals ?? 1), significand: 1)
        return "\(decimalAmount * power) \(swapPayload?.fromCoin.ticker ?? "")"
    }
    
    var fromAmountFiatString: String {
        let newValueFiat = (Decimal(string: swapPayload?.fromAmount.description ?? "") ?? Decimal.zero) * Decimal(swapPayload?.fromCoin.price ?? 1)
        let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2)
        let power = Decimal(sign: .plus, exponent: -(swapPayload?.fromCoin.decimals ?? 1), significand: 1)
        return NSDecimalNumber(decimal: truncatedValueFiat * power).stringValue.formatToFiat()
    }

    var toAmountString: String {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -coin.decimals, significand: 1)
        return "\(decimalAmount * power) \(coin.ticker)"
    }
    
    var toAmountFiatString: String {
        swapPayload?.toCoin.fiat(decimal: swapPayload?.toAmountDecimal ?? 0).description ?? ""
    }

    static let example = KeysignPayload(coin: Coin.example, toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100, sendMaxAmount: false), utxos: [], memo: "Memo", swapPayload: nil, approvePayload: nil, vaultPubKeyECDSA: "12345", vaultLocalPartyID: "iPhone-100")
}
