import Foundation
import WalletCore

class TokensStore {
    static var TokenSelectionAssets = [
        CoinMeta(chain: Chain.bitcoin, ticker: "BTC", logo: "btc", decimals: 8,  priceProviderId: "bitcoin", contractAddress: "",isNativeToken: true),
        
        CoinMeta(chain: Chain.bitcoinCash, ticker: "BCH", logo: "bch",  decimals: 8, priceProviderId: "bitcoin-cash", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.litecoin, ticker: "LTC", logo: "ltc",   decimals: 8,   priceProviderId: "litecoin", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.dogecoin, ticker: "DOGE", logo: "doge",   decimals: 8,  priceProviderId: "dogecoin", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.dash, ticker: "DASH", logo: "dash",   decimals: 8,   priceProviderId: "dash", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.thorChain, ticker: "RUNE", logo: "rune",  decimals: 8,   priceProviderId: "thorchain", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.mayaChain, ticker: "CACAO", logo: "cacao",   decimals: 10,   priceProviderId: "cacao", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.mayaChain, ticker: "MAYA", logo: "maya",   decimals: 4,   priceProviderId: "maya", contractAddress: "",  isNativeToken: false),
        
        CoinMeta(chain: Chain.ethereum, ticker: "ETH", logo: "eth",   decimals: 18,   priceProviderId: "ethereum", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.ethereum, ticker: "USDC", logo: "usdc",  decimals: 6,   priceProviderId: "usd-coin", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",  isNativeToken: false),
        
        CoinMeta(chain: Chain.ethereum, ticker: "USDT", logo: "usdt", decimals: 6,  priceProviderId: "tether", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7",  isNativeToken: false),
        
        CoinMeta(chain: Chain.ethereum, ticker: "UNI", logo: "uni",   decimals: 18,   priceProviderId: "uniswap", contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984",  isNativeToken: false),
        
        CoinMeta(chain: Chain.ethereum, ticker: "MATIC", logo: "matic",   decimals: 18,  priceProviderId: "matic-network", contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0",  isNativeToken: false),
        
        CoinMeta(chain: Chain.ethereum, ticker: "WBTC", logo: "wbtc",  decimals: 8,   priceProviderId: "wrapped-bitcoin", contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599",  isNativeToken: false),
        
        CoinMeta(chain: Chain.ethereum, ticker: "LINK", logo: "link",  decimals: 18,   priceProviderId: "chainlink", contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca",  isNativeToken: false ),
        
        CoinMeta(chain: Chain.ethereum, ticker: "FLIP", logo: "flip",  decimals: 18,   priceProviderId: "chainflip", contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a",  isNativeToken: false ),
        
        CoinMeta(chain: Chain.ethereum, ticker: "TGT", logo: "tgt",  decimals: 18,   priceProviderId: "thorwallet", contractAddress: "0x108a850856Db3f85d0269a2693D896B394C80325",  isNativeToken: false ),
        
        CoinMeta(chain: Chain.ethereum, ticker: "FOX", logo: "fox",  decimals: 18,   priceProviderId: "shapeshift-fox-token", contractAddress: "0xc770eefad204b5180df6a14ee197d99d808ee52d",  isNativeToken: false ),
        
        CoinMeta(chain: Chain.solana, ticker: "SOL", logo: "solana",   decimals: 9,  priceProviderId: "solana", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.avalanche, ticker: "AVAX", logo: "avax",   decimals: 18,   priceProviderId: "avalanche-2", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.avalanche, ticker: "USDC", logo: "usdc",  decimals: 6,   priceProviderId: "usd-coin", contractAddress: "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e",  isNativeToken: false),
        
        CoinMeta(chain: Chain.bscChain, ticker: "BNB", logo: "bsc",   decimals: 18,   priceProviderId: "binancecoin", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.bscChain, ticker: "USDT", logo: "usdt",   decimals: 18,   priceProviderId: "tether", contractAddress: "0x55d398326f99059fF775485246999027B3197955",  isNativeToken: false),
        
        CoinMeta(chain: Chain.bscChain, ticker: "USDC", logo: "usdc",  decimals: 18,   priceProviderId: "usd-coin", contractAddress: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d",  isNativeToken: false),
        
        CoinMeta(chain: Chain.gaiaChain, ticker: "ATOM", logo: "atom",   decimals: 6,   priceProviderId: "cosmos", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.kujira, ticker: "KUJI", logo: "kuji",   decimals: 6,  priceProviderId: "kujira", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.dydx, ticker: "DYDX", logo: "dydx",   decimals: 18,  priceProviderId: "dydx-chain", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.base, ticker: "ETH", logo: "eth_base",   decimals: 18,   priceProviderId: "ethereum", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.base, ticker: "USDC", logo: "usdc",   decimals: 6,  priceProviderId: "usd-coin", contractAddress: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",  isNativeToken: false ),
        
        CoinMeta(chain: Chain.arbitrum, ticker: "ETH", logo: "eth_arbitrum",   decimals: 18,   priceProviderId: "ethereum", contractAddress: "",  isNativeToken: true), //Arbitrum asks for more fee otherwise it says the intrinsic gas too low
        
        CoinMeta(chain: Chain.arbitrum, ticker: "ARB", logo: "arbitrum",   decimals: 18,   priceProviderId: "arbitrum", contractAddress: "0x912CE59144191C1204E64559FE8253a0e49E6548",  isNativeToken: false),
        
        CoinMeta(chain: Chain.arbitrum, ticker: "TGT", logo: "tgt",   decimals: 18,   priceProviderId: "thorwallet", contractAddress: "0x429fEd88f10285E61b12BDF00848315fbDfCC341",  isNativeToken: false),
        
        CoinMeta(chain: Chain.arbitrum, ticker: "FOX", logo: "fox",  decimals: 18,  priceProviderId: "shapeshift-fox-token", contractAddress: "0xf929de51D91C77E42f5090069E0AD7A09e513c73",  isNativeToken: false),
        
        CoinMeta(chain: Chain.optimism, ticker: "ETH", logo: "eth_optimism",  decimals: 18,   priceProviderId: "ethereum", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.optimism, ticker: "OP", logo: "optimism",  decimals: 18,   priceProviderId: "optimism", contractAddress: "0x4200000000000000000000000000000000000042",  isNativeToken: false),
        
        CoinMeta(chain: Chain.optimism, ticker: "FOX", logo: "fox",   decimals: 18,   priceProviderId: "shapeshift-fox-token", contractAddress: "0xf1a0da3367bc7aa04f8d94ba57b862ff37ced174",  isNativeToken: false),
        
        CoinMeta(chain: Chain.polygon, ticker: "MATIC", logo: "matic",   decimals: 18,   priceProviderId: "matic-network", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.polygon, ticker: "WETH", logo: "wETH",  decimals: 18,   priceProviderId: "ethereum", contractAddress: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",  isNativeToken: false),
        
        CoinMeta(chain: Chain.polygon, ticker: "FOX", logo: "fox",  decimals: 18,   priceProviderId: "shapeshift-fox-token", contractAddress: "0x65a05db8322701724c197af82c9cae41195b0aa8",  isNativeToken: false),
        
        CoinMeta(chain: Chain.blast, ticker: "ETH", logo: "eth_blast",   decimals: 18,   priceProviderId: "ethereum", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.blast, ticker: "WETH", logo: "wETH",  decimals: 18,   priceProviderId: "ethereum", contractAddress: "0x4300000000000000000000000000000000000004",  isNativeToken: false),
        
        CoinMeta(chain: Chain.cronosChain, ticker: "CRO", logo: "cro",  decimals: 18,  priceProviderId: "crypto-com-chain", contractAddress: "",  isNativeToken: true),
        
        CoinMeta(chain: Chain.sui, ticker: "SUI", logo: "sui",   decimals: 9,   priceProviderId: "sui", contractAddress: "",  isNativeToken: true), //0.5 SUI limit
        
        CoinMeta(chain: Chain.polkadot, ticker: "DOT", logo: "dot",   decimals: 10,   priceProviderId: "polkadot", contractAddress: "",  isNativeToken: true), //find the default fee per unit
        
        CoinMeta(chain: Chain.zksync, ticker: "ETH", logo: "zsync_era",   decimals: 18,   priceProviderId: "ethereum", contractAddress: "",  isNativeToken: true),
        
    ]
    
    static func getNativeToken(coin: Coin) throws -> Coin {
        if coin.isNativeToken {
            return coin
        }
        guard let nativeToken = TokenSelectionAssets.first(where: { $0.isNativeToken && $0.chain == coin.chain }) else {
            throw TokenSelectionAssetError.error(message: "We could not find the native/parent token for the token \(coin.ticker)")
        }
        return nativeToken.toCoin(address: coin.address, hexPublicKey: coin.hexPublicKey)
    }
    
    static func getCoin(_ ticker: String, coinType: CoinType, address: String,hexPublicKey: String) -> Coin? {
        return TokenSelectionAssets.first(where: { $0.ticker == ticker && $0.coinType == coinType}).map{$0.toCoin(address: address, hexPublicKey: hexPublicKey)} ?? nil
    }
    
    static func createNewCoinInstance(ticker: String, address: String, hexPublicKey: String, coinType: CoinType) -> Result<Coin, Error> {
        guard let templateCoin = getCoin(ticker, coinType: coinType,address: address,hexPublicKey: hexPublicKey) else {
            return .failure(HelperError.runtimeError("doesn't support coin \(ticker)"))
        }
        
        return .success(templateCoin)
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
