import Foundation
import WalletCore

class TokensStore {
    static var TokenSelectionAssets = [
        Coin(chain: Chain.bitcoin, ticker: "BTC", logo: "btc", address: "", priceRate: 0.0,  decimals: "8", hexPublicKey: "", priceProviderId: "bitcoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "20"),
        
        Coin(chain: Chain.bitcoinCash, ticker: "BCH", logo: "bch", address: "", priceRate: 0.0,  decimals: "8", hexPublicKey: "", priceProviderId: "bitcoin-cash", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "20"),
        
        Coin(chain: Chain.litecoin, ticker: "LTC", logo: "ltc", address: "", priceRate: 0.0,  decimals: "8", hexPublicKey: "",  priceProviderId: "litecoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "1000"),
        
        Coin(chain: Chain.dogecoin, ticker: "DOGE", logo: "doge", address: "", priceRate: 0.0,  decimals: "8", hexPublicKey: "", priceProviderId: "dogecoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "1000000"),
        
        Coin(chain: Chain.dash, ticker: "DASH", logo: "dash", address: "", priceRate: 0.0,  decimals: "8", hexPublicKey: "",  priceProviderId: "dash", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "20"),
        
        Coin(chain: Chain.thorChain, ticker: "RUNE", logo: "rune", address: "", priceRate: 0.0, decimals: "8", hexPublicKey: "",  priceProviderId: "thorchain", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "2000000"),
        
        Coin(chain: Chain.mayaChain, ticker: "CACAO", logo: "cacao", address: "", priceRate: 0.0,  decimals: "10", hexPublicKey: "",  priceProviderId: "cacao", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "2000000000"),
        
        Coin(chain: Chain.mayaChain, ticker: "MAYA", logo: "maya", address: "", priceRate: 0.0,  decimals: "4", hexPublicKey: "",  priceProviderId: "maya", contractAddress: "", rawBalance: "0", isNativeToken: false, feeDefault: "2000000000"),
        
        Coin(chain: Chain.ethereum, ticker: "ETH", logo: "eth", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "ethereum", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.ethereum, ticker: "USDC", logo: "usdc", address: "", priceRate: 1.0,  decimals: "6", hexPublicKey: "",  priceProviderId: "usd-coin", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "USDT", logo: "usdt", address: "", priceRate: 1.0, decimals: "6", hexPublicKey: "", priceProviderId: "tether", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "UNI", logo: "uni", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "uniswap", contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "MATIC", logo: "matic", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "", priceProviderId: "matic-network", contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "WBTC", logo: "wbtc", address: "", priceRate: 0.0, decimals: "8", hexPublicKey: "",  priceProviderId: "wrapped-bitcoin", contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "LINK", logo: "link", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "chainlink", contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "FLIP", logo: "flip", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "chainflip", contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "TGT", logo: "tgt", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "thorwallet", contractAddress: "0x108a850856Db3f85d0269a2693D896B394C80325", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.ethereum, ticker: "FOX", logo: "fox", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "shapeshift-fox-token", contractAddress: "0xc770eefad204b5180df6a14ee197d99d808ee52d", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.solana, ticker: "SOL", logo: "solana", address: "", priceRate: 0.0,  decimals: "9", hexPublicKey: "", priceProviderId: "solana", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "7000"),
        
        Coin(chain: Chain.avalanche, ticker: "AVAX", logo: "avax", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "avalanche-2", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.avalanche, ticker: "USDC", logo: "usdc", address: "", priceRate: 0.0, decimals: "6", hexPublicKey: "",  priceProviderId: "usd-coin", contractAddress: "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.bscChain, ticker: "BNB", logo: "bsc", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "binancecoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.bscChain, ticker: "USDT", logo: "usdt", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "tether", contractAddress: "0x55d398326f99059fF775485246999027B3197955", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.bscChain, ticker: "USDC", logo: "usdc", address: "", priceRate: 1.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "usd-coin", contractAddress: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.gaiaChain, ticker: "ATOM", logo: "atom", address: "", priceRate: 0.0,  decimals: "6", hexPublicKey: "",  priceProviderId: "cosmos", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "200000"),
        
        Coin(chain: Chain.kujira, ticker: "KUJI", logo: "kuji", address: "", priceRate: 0.0,  decimals: "6", hexPublicKey: "", priceProviderId: "kujira", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "200000"),
        
        Coin(chain: Chain.base, ticker: "ETH", logo: "eth_base", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "ethereum", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.base, ticker: "USDC", logo: "usdc", address: "", priceRate: 0.0,  decimals: "6", hexPublicKey: "", priceProviderId: "usd-coin", contractAddress: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.arbitrum, ticker: "ETH", logo: "eth_arbitrum", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "ethereum", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "120000"), //Arbitrum asks for more fee otherwise it says the intrinsic gas too low
        
        Coin(chain: Chain.arbitrum, ticker: "ARB", logo: "arbitrum", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "arbitrum", contractAddress: "0x912CE59144191C1204E64559FE8253a0e49E6548", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.arbitrum, ticker: "TGT", logo: "tgt", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "thorwallet", contractAddress: "0x429fEd88f10285E61b12BDF00848315fbDfCC341", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.arbitrum, ticker: "FOX", logo: "fox", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "", priceProviderId: "shapeshift-fox-token", contractAddress: "0xf929de51D91C77E42f5090069E0AD7A09e513c73", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.optimism, ticker: "ETH", logo: "eth_optimism", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "ethereum", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.optimism, ticker: "OP", logo: "optimism", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "optimism", contractAddress: "0x4200000000000000000000000000000000000042", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.optimism, ticker: "FOX", logo: "fox", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "shapeshift-fox-token", contractAddress: "0xf1a0da3367bc7aa04f8d94ba57b862ff37ced174", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.polygon, ticker: "MATIC", logo: "matic", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "matic-network", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.polygon, ticker: "WETH", logo: "wETH", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "ethereum", contractAddress: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.polygon, ticker: "FOX", logo: "fox", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "shapeshift-fox-token", contractAddress: "0x65a05db8322701724c197af82c9cae41195b0aa8", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.blast, ticker: "ETH", logo: "eth_blast", address: "", priceRate: 0.0,  decimals: "18", hexPublicKey: "",  priceProviderId: "ethereum", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.blast, ticker: "WETH", logo: "wETH", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "",  priceProviderId: "ethereum", contractAddress: "0x4300000000000000000000000000000000000004", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.cronosChain, ticker: "CRO", logo: "cro", address: "", priceRate: 0.0, decimals: "18", hexPublicKey: "", priceProviderId: "crypto-com-chain", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "23000"),
        
        Coin(chain: Chain.sui, ticker: "SUI", logo: "sui", address: "", priceRate: 0.0,  decimals: "9", hexPublicKey: "",  priceProviderId: "sui", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "500000000"), //0.5 SUI limit
        
        Coin(chain: Chain.polkadot, ticker: "DOT", logo: "dot", address: "", priceRate: 0.0,  decimals: "10", hexPublicKey: "",  priceProviderId: "polkadot", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "10000000000"), //find the default fee per unit
        
    ]
    
    static func getNativeToken(coin: Coin) throws -> Coin {
        if coin.isNativeToken {
            return coin
        }
        guard let nativeToken = TokenSelectionAssets.first(where: { $0.isNativeToken && $0.chain == coin.chain }) else {
            throw TokenSelectionAssetError.error(message: "We could not find the native/parent token for the token \(coin.ticker)")
        }
        return nativeToken
    }
    
    static func getCoin(_ ticker: String, coinType: CoinType) -> Coin? {
        return TokenSelectionAssets.first(where: { $0.ticker == ticker && $0.coinType == coinType}) ?? nil
    }
    
    static func createNewCoinInstance(ticker: String, address: String, hexPublicKey: String, coinType: CoinType) -> Result<Coin, Error> {
        guard let templateCoin = getCoin(ticker, coinType: coinType) else {
            return .failure(HelperError.runtimeError("doesn't support coin \(ticker)"))
        }
        let clonedCoin = templateCoin.clone()
        clonedCoin.address = address
        clonedCoin.id = "\(clonedCoin.chain.rawValue)-\(clonedCoin.ticker)-\(clonedCoin.address)"
        clonedCoin.hexPublicKey = hexPublicKey
        return .success(clonedCoin)
    }
    
    enum TokenSelectionAssetError: Error {
        case error(message: String)
        
        var localizedDescription: String {
            switch self {
            case let .error(message):
                return "Error: \(message)"
            }
        }
    }
}
