//
//  Endpoint.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import Foundation

class Endpoint {
    static let broadcastTransaction = "https://mempool.space/api/tx"
    
    static let broadcastTransactionThorchainNineRealms = "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs"
    
    static let web3ServiceInfura = "https://mainnet.infura.io/v3/\(AppConfiguration.infuraApiKey)"
    
    // With parameters
    static func bitcoinLabelTxHash(_ value: String) -> String {
        "https://mempool.space/tx/\(value)"
    }
    
    static func ethereumLabelTxHash(_ value: String) -> String {
        "https://etherscan.io/tx/\(value)"
    }
        
    static func fetchUnspentOutputs(_ value: String) -> String {
        "https://api.blockcypher.com/v1/btc/main/addrs/\(value)?unspentOnly=true"
    }
    
    static func fetchCryptoPrices(coin: String, fiat: String) -> String {
        "https://api.coingecko.com/api/v3/simple/price?ids=\(coin)&vs_currencies=\(fiat)"
    }
    
    static func fetchBitcoinTransactions(_ userAddress: String) -> String {
        "https://mempool.space/api/address/\(userAddress)/txs"
    }
    
    static func getEthInfo(_ address: String) -> String {
        "https://api.ethplorer.io/getAddressInfo/\(address)?apiKey=freekey"
    }
    
    static func broadcastEtherscanTransaction(hex: String, apiKey: String) -> String {
        "https://api.etherscan.io/api?module=proxy&action=eth_sendRawTransaction&hex=\(hex)&apikey=\(apiKey)"
    }
    
    static func fetchEtherscanTransactions(address: String, apiKey: String) -> String {
        "https://api.etherscan.io/api?module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&sort=asc&apikey=\(apiKey)"
    }
    
    static func fetchERC20Transactions(address: String, apiKey: String, contractAddress: String) -> String {
        "https://api.etherscan.io/api?module=account&action=tokentx&contractaddress=\(contractAddress)&address=\(address)&startblock=0&endblock=99999999&sort=asc&apikey=\(apiKey)"
    }
}
