//
//  CryptocurrencyHelperProtocol.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 25/02/2024.
//

import Foundation
import Tss
import WalletCore

protocol CoinHelperProtocol {
    func validateAddress(_ address: String) -> Bool
    func getSignatureFromTssResponse(tssResponse: TssKeysignResponse) -> Result<Data, Error>
    func getCoinDetails(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error>
    func getPublicKey(hexPubKey: String, hexChainCode: String) -> String
    func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error>
    func getPreSigningImageHash(utxos: [UtxoInfo], fromAddress: String, toAddress: String, toAmount: Int64, byteFee: Int64, memo: String?) -> Result<[String], Error>
    func getSigningInput(utxos: [UtxoInfo], fromAddress: String, toAddress: String, toAmount: Int64, byteFee: Int64, memo: String?) -> Result<BitcoinSigningInput, Error>
    func getPreSigningInputData(utxos: [UtxoInfo], fromAddress: String, toAddress: String, toAmount: Int64, byteFee: Int64, memo: String?) -> Result<Data, Error>
    func getTransactionPlan(utxos: [UtxoInfo], fromAddress: String, toAddress: String, toAmount: Int64, byteFee: Int64, memo: String?) -> Result<BitcoinTransactionPlan, Error>
    func getSignedTransaction(utxos: [UtxoInfo], hexPubKey: String, fromAddress: String, toAddress: String, toAmount: Int64, byteFee: Int64, memo: String?, signatureProvider: (Data) -> Data) -> Result<String, Error>
}

