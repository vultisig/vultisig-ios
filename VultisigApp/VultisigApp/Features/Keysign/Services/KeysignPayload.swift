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
    let libType: String
    let wasmExecuteContractPayload: WasmExecuteContractPayload?
    let tronTransferContractPayload: TronTransferContractPayload?
    let tronTriggerSmartContractPayload: TronTriggerSmartContractPayload?
    let tronTransferAssetContractPayload: TronTransferAssetContractPayload?
    let skipBroadcast: Bool
    let signData: SignData?

    var signAmino: SignAmino? {
        guard case let .signAmino(amino) = signData else {
            return nil
        }
        return amino
    }

    var signDirect: SignDirect? {
        guard case let .signDirect(direct) = signData else {
            return nil
        }
        return direct
    }

    var signSolana: SignSolana? {
        guard case let .signSolana(solana) = signData else {
            return nil
        }
        return solana
    }

    var fromAmountString: String {
        let decimalAmount = Decimal(string: swapPayload?.fromAmount.description ?? "") ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -(swapPayload?.fromCoin.decimals ?? 1), significand: 1)
        return "\((decimalAmount * power).formatForDisplay()) \(swapPayload?.fromCoin.ticker ?? "")"
    }

    var fromAmountFiatString: String {
        let newValueFiat = (Decimal(string: swapPayload?.fromAmount.description ?? "") ?? Decimal.zero) * Decimal(swapPayload?.fromCoin.price ?? 1)
        let truncatedValueFiat = newValueFiat.truncated(toPlaces: 2)
        let power = Decimal(sign: .plus, exponent: -(swapPayload?.fromCoin.decimals ?? 1), significand: 1)
        return NSDecimalNumber(decimal: truncatedValueFiat * power).stringValue
    }

    var toAmountWithTickerString: String {
        return "\(toAmountString) \(coin.ticker)"
    }

    var toAmountDecimal: Decimal {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -coin.decimals, significand: 1)
        return decimalAmount * power
    }

    var toAmountString: String {
        return toAmountDecimal.formatForDisplay()
    }

    var toSwapAmountFiatString: String {
        swapPayload?.toCoin.fiat(decimal: swapPayload?.toAmountDecimal ?? 0).description ?? ""
    }

    var toSendAmountFiatString: String {
        return coin.fiat(decimal: toAmountDecimal).description
    }

    static let example = KeysignPayload(
        coin: Coin.example,
        toAddress: "toAddress",
        toAmount: 100,
        chainSpecific: BlockChainSpecific.UTXO(byteFee: 100, sendMaxAmount: false),
        utxos: [],
        memo: "Memo",
        swapPayload: nil,
        approvePayload: nil,
        vaultPubKeyECDSA: "12345",
        vaultLocalPartyID: "iPhone-100",
        libType: LibType.DKLS.toString(),
        wasmExecuteContractPayload: nil,
        tronTransferContractPayload: nil,
        tronTriggerSmartContractPayload: nil,
        tronTransferAssetContractPayload: nil,
        skipBroadcast: false,
        signData: nil
    )
}
