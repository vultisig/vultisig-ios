import Foundation

enum CoinFactoryError: Error {
    case unsupportedCoinType
}

class CoinFactory {
    static func createCoinHelper(for type: Coin) throws -> CoinHelperProtocol {
        switch type.chain.ticker {
            case "BTC":
                return BitcoinHelper()
            case "ETH":
                return EthereumHelper()
            default:
                throw CoinFactoryError.unsupportedCoinType
        }
    }
    
    static func createCoinHelper(for ticker: String) throws -> CoinHelperProtocol {
        switch ticker {
            case "BTC":
                return BitcoinHelper()
            case "ETH":
                return EthereumHelper()
            default:
                throw CoinFactoryError.unsupportedCoinType
        }
    }
}
