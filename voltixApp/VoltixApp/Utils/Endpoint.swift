    //
    //  Endpoint.swift
    //  VoltixApp
    //
    //  Created by Amol Kumar on 2024-03-05.
    //

import Foundation

class Endpoint {
    static let btcBroadcastTransaction = "https://mempool.space/api/tx"
	
	static let ltcBroadcastTransaction = "https://litecoinspace.org/api/tx"
    
    static let broadcastTransactionThorchainNineRealms = "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs"
    
    static func fetchAccountNumberThorchainNineRealms(_ address: String) -> String {
        "https://thornode.ninerealms.com/auth/accounts/\(address)"
    }
	
	static let solanaServiceAlchemyRpc = "http://45.76.120.223/alchemy/"

	static let web3ServiceInfura = "http://45.76.120.223/infura"

	static func bitcoinLabelTxHash(_ value: String) -> String {
        "https://mempool.space/tx/\(value)"
    }
	
	static func litecoinLabelTxHash(_ value: String) -> String {
		"https://litecoinspace.org/tx/\(value)"
	}
	
	static func blockchairDashboard(_ address: String, _ coinName: String) -> String {
		"https://api.blockchair.com/\(coinName)/dashboards/address/\(address)?key=A___PLqLolRBKDsYRO9SUi5EzgeXjMt5"
	}
	
    static func ethereumLabelTxHash(_ value: String) -> String {
        "https://etherscan.io/tx/\(value)"
    }
    
    static func fetchUnspentOutputs(_ value: String) -> String {
		"http://45.76.120.223/blockcypher/v1/btc/main/addrs/\(value)?unspentOnly=true"
    }
	
	static func fetchLitecoinUnspentOutputs(_ userAddress: String) -> String {
		"https://litecoinspace.org/api/address/\(userAddress)/utxo"
	}
	
    static func fetchCryptoPrices(coin: String, fiat: String) -> String {
        "https://api.coingecko.com/api/v3/simple/price?ids=\(coin)&vs_currencies=\(fiat)"
    }
    
    static func fetchBitcoinTransactions(_ userAddress: String) -> String {
        "https://mempool.space/api/address/\(userAddress)/txs"
    }

	static func fetchLitecoinTransactions(_ userAddress: String) -> String {
		"https://litecoinspace.org/api/address/\(userAddress)/txs"
	}

    static func getEthInfo(_ address: String) -> String {
        "https://api.ethplorer.io/getAddressInfo/\(address)?apiKey=freekey"
    }
    
    static func broadcastEtherscanTransaction(hex: String) -> String {
        "http://45.76.120.223/etherscan/api?module=proxy&action=eth_sendRawTransaction&hex=\(hex)"
    }
    
    static func fetchEtherscanTransactions(address: String) -> String {
        "http://45.76.120.223/etherscan/api?module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&sort=asc"
    }
    
    static func fetchERC20Transactions(address: String, contractAddress: String) -> String {
        "http://45.76.120.223/etherscan/api?module=account&action=tokentx&contractaddress=\(contractAddress)&address=\(address)&startblock=0&endblock=99999999&sort=asc"
    }
}
