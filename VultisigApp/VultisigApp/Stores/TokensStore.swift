import Foundation
import WalletCore

class TokensStore {

    struct Token {
        static var bitcoin: CoinMeta {
            CoinMeta(chain: Chain.bitcoin, ticker: "BTC", logo: "btc", decimals: 8, priceProviderId: "bitcoin", contractAddress: "", isNativeToken: true)
        }

        static var bitcoinCash: CoinMeta {
            CoinMeta(chain: Chain.bitcoinCash, ticker: "BCH", logo: "bch", decimals: 8, priceProviderId: "bitcoin-cash", contractAddress: "", isNativeToken: true)
        }

        static var litecoin: CoinMeta {
            CoinMeta(chain: Chain.litecoin, ticker: "LTC", logo: "ltc", decimals: 8, priceProviderId: "litecoin", contractAddress: "", isNativeToken: true)
        }

        static var dogecoin: CoinMeta {
            CoinMeta(chain: Chain.dogecoin, ticker: "DOGE", logo: "doge", decimals: 8, priceProviderId: "dogecoin", contractAddress: "", isNativeToken: true)
        }

        static var dash: CoinMeta {
            CoinMeta(chain: Chain.dash, ticker: "DASH", logo: "dash", decimals: 8, priceProviderId: "dash", contractAddress: "", isNativeToken: true)
        }

        static var thorChain: CoinMeta {
            CoinMeta(chain: Chain.thorChain, ticker: "RUNE", logo: "rune", decimals: 8, priceProviderId: "thorchain", contractAddress: "", isNativeToken: true)
        }

        static var mayaChainCacao: CoinMeta {
            CoinMeta(chain: Chain.mayaChain, ticker: "CACAO", logo: "cacao", decimals: 10, priceProviderId: "cacao", contractAddress: "", isNativeToken: true)
        }

        static var mayaChainMaya: CoinMeta {
            CoinMeta(chain: Chain.mayaChain, ticker: "MAYA", logo: "maya", decimals: 4, priceProviderId: "maya", contractAddress: "", isNativeToken: false)
        }

        static var ethereum: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }

        static var ethereumUsdc: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", isNativeToken: false)
        }

        static var ethereumUsdt: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "USDT", logo: "usdt", decimals: 6, priceProviderId: "tether", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7", isNativeToken: false)
        }

        static var ethereumUni: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "UNI", logo: "uni", decimals: 18, priceProviderId: "uniswap", contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", isNativeToken: false)
        }

        static var ethereumMatic: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "MATIC", logo: "matic", decimals: 18, priceProviderId: "matic-network", contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", isNativeToken: false)
        }

        static var ethereumWbtc: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "WBTC", logo: "wbtc", decimals: 8, priceProviderId: "wrapped-bitcoin", contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", isNativeToken: false)
        }

        static var ethereumLink: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "LINK", logo: "link", decimals: 18, priceProviderId: "chainlink", contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca", isNativeToken: false)
        }

        static var ethereumFlip: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "FLIP", logo: "flip", decimals: 18, priceProviderId: "chainflip", contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a", isNativeToken: false)
        }

        static var ethereumTgt: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "TGT", logo: "tgt", decimals: 18, priceProviderId: "thorwallet", contractAddress: "0x108a850856Db3f85d0269a2693D896B394C80325", isNativeToken: false)
        }

        static var ethereumFox: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "FOX", logo: "fox", decimals: 18, priceProviderId: "shapeshift-fox-token", contractAddress: "0xc770eefad204b5180df6a14ee197d99d808ee52d", isNativeToken: false)
        }

        static var solana: CoinMeta {
            CoinMeta(chain: Chain.solana, ticker: "SOL", logo: "solana", decimals: 9, priceProviderId: "solana", contractAddress: "", isNativeToken: true)
        }

        static var avalanche: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "AVAX", logo: "avax", decimals: 18, priceProviderId: "avalanche-2", contractAddress: "", isNativeToken: true)
        }

        static var avalancheUsdc: CoinMeta {
            CoinMeta(chain: Chain.avalanche, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e", isNativeToken: false)
        }

        static var bscChainBnb: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "BNB", logo: "bsc", decimals: 18, priceProviderId: "binancecoin", contractAddress: "", isNativeToken: true)
        }

        static var bscChainUsdt: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "USDT", logo: "usdt", decimals: 18, priceProviderId: "tether", contractAddress: "0x55d398326f99059fF775485246999027B3197955", isNativeToken: false)
        }

        static var bscChainUsdc: CoinMeta {
            CoinMeta(chain: Chain.bscChain, ticker: "USDC", logo: "usdc", decimals: 18, priceProviderId: "usd-coin", contractAddress: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", isNativeToken: false)
        }

        static var gaiaChainAtom: CoinMeta {
            CoinMeta(chain: Chain.gaiaChain, ticker: "ATOM", logo: "atom", decimals: 6, priceProviderId: "cosmos", contractAddress: "", isNativeToken: true)
        }

        static var kujira: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "KUJI", logo: "kuji", decimals: 6, priceProviderId: "kujira", contractAddress: "", isNativeToken: true)
        }

        static var dydx: CoinMeta {
            CoinMeta(chain: Chain.dydx, ticker: "DYDX", logo: "dydx", decimals: 18, priceProviderId: "dydx-chain", contractAddress: "", isNativeToken: true)
        }

        static var baseEth: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "ETH", logo: "eth_base", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }

        static var baseUsdc: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", isNativeToken: false)
        }

        static var baseWewe: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "WEWE", logo: "wewe", decimals: 18, priceProviderId: "", contractAddress: "0x6b9bb36519538e0C073894E964E90172E1c0B41E", isNativeToken: false)
        }
    }

    static var TokenSelectionAssets = [
        TokensStore.Token.bitcoin,
        TokensStore.Token.bitcoinCash,
        TokensStore.Token.litecoin,
        TokensStore.Token.dogecoin,
        TokensStore.Token.dash,
        TokensStore.Token.thorChain,
        TokensStore.Token.mayaChainCacao,
        TokensStore.Token.mayaChainMaya,
        TokensStore.Token.ethereum,
        TokensStore.Token.ethereumUsdc,
        TokensStore.Token.ethereumUsdt,
        TokensStore.Token.ethereumUni,
        TokensStore.Token.ethereumMatic,
        TokensStore.Token.ethereumWbtc,
        TokensStore.Token.ethereumLink,
        TokensStore.Token.ethereumFlip,
        TokensStore.Token.ethereumTgt,
        TokensStore.Token.ethereumFox,
        TokensStore.Token.solana,
        TokensStore.Token.avalanche,
        TokensStore.Token.avalancheUsdc,
        TokensStore.Token.bscChainBnb,
        TokensStore.Token.bscChainUsdt,
        TokensStore.Token.bscChainUsdc,
        TokensStore.Token.gaiaChainAtom,
        TokensStore.Token.kujira,
        TokensStore.Token.dydx,
        TokensStore.Token.baseEth,
        TokensStore.Token.baseUsdc,
        TokensStore.Token.baseWewe
    ]

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
