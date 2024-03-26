//
//  Endpoint.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import Foundation

class Endpoint {
	
	static let broadcastTransactionThorchainNineRealms = "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs"
	
	static func fetchAccountNumberThorchainNineRealms(_ address: String) -> String {
		"https://thornode.ninerealms.com/auth/accounts/\(address)"
	}
	static func fetchAccountBalanceThorchainNineRealms(address: String) -> String{
		"https://thornode.ninerealms.com/cosmos/bank/v1beta1/balances/\(address)"
	}
    
    static let solanaServiceAlchemyRpc = "http://45.76.120.223/alchemy/"
	    
    static func bitcoinLabelTxHash(_ value: String) -> String {
		"https://mempool.space/tx/\(value)"
	}
    
    static func litecoinLabelTxHash(_ value: String) -> String {
        "https://litecoinspace.org/tx/\(value)"
    }
    
    static func blockchairStats(_ chainName: String) -> String {
        "http://45.76.120.223/blockchair/\(chainName)/stats"
    }
    
    static func blockchairBroadcast(_ chainName: String) -> String {
        "http://45.76.120.223/blockchair/\(chainName)/push/transaction"
    }
    
    static func blockchairDashboard(_ address: String, _ coinName: String) -> String {
        "http://45.76.120.223/blockchair/\(coinName)/dashboards/address/\(address)"
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
	    
	static func broadcastEtherscanTransaction(hex: String) -> String {
		"http://45.76.120.223/etherscan/api?module=proxy&action=eth_sendRawTransaction&hex=\(hex)"
	}
	
	static func fetchEtherscanTransactions(address: String) -> String {
		"http://45.76.120.223/etherscan/api?module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&sort=asc"
	}
	
	static func fetchEtherscanTransactionCount(address: String) -> String {
		"http://45.76.120.223/etherscan/api?module=proxy&action=eth_getTransactionCount&address=\(address)&tag=latest"
	}
	
	static func fetchEtherscanBalance(address: String) -> String {
		"http://45.76.120.223/etherscan/api?module=account&action=balance&address=\(address)&tag=latest"
	}
	
	static func fetchEtherscanTokenBalance(contractAddress: String, address: String) -> String {
		"http://45.76.120.223/etherscan/api?module=account&action=tokenbalance&contractaddress=\(contractAddress)&address=\(address)&tag=latest"
	}
	
	static func fetchEtherscanEstimateGasForEthTransaction(data: String, to: String, valueHex: String) -> String {
		"http://45.76.120.223/etherscan/api?module=proxy&action=eth_estimateGas&data=\(data)&to=\(to)&value=\(valueHex)"
	}
	
	static func fetchEtherscanEstimateGasForERC20Transaction(data: String, contractAddress: String) -> String {
		"http://45.76.120.223/etherscan/api?module=proxy&action=eth_estimateGas&data=\(data)&to=\(contractAddress)"
	}
	
	static func fetchEtherscanGasPrice() -> String {
		"http://45.76.120.223/etherscan/api?module=proxy&action=eth_gasPrice"
	}
	
	static func fetchEtherscanAddressTokensBalance(address: String) -> String {
		"http://45.76.120.223/etherscan/api?module=account&action=addresstokenbalance&address=\(address)&page=1&offset=100"
	}
	
	static func fetchERC20Transactions(address: String, contractAddress: String) -> String {
		"http://45.76.120.223/etherscan/api?module=account&action=tokentx&contractaddress=\(contractAddress)&address=\(address)&startblock=0&endblock=99999999&sort=asc"
	}
    static func getExplorerURL(chainTicker: String, txid: String) -> String{
        switch chainTicker {
        case "BTC":
            return "https://blockchair.com/bitcoin/transaction/\(txid)"
        case "BCH":
            return "https://blockchair.com/bitcoin-cash/transaction/\(txid)"
        case "LTC":
            return "https://blockchair.com/litecoin/transaction/\(txid)"
        case "DOGE":
            return "https://blockchair.com/dogecoin/transaction/\(txid)"
        case "RUNE":
            return "https://runescan.io/tx/\(txid)"
        case "SOL":
            return "https://explorer.solana.com/tx/\(txid)"
        case "ETH":
            return "https://etherscan.io/tx/\(txid)"
        default:
            return ""
        }
    }
}
