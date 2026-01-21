import Foundation

extension TokensStore {
    struct Token {
        static var ethereum: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        static var ethereumUsdc: CoinMeta {
            CoinMeta(chain: Chain.ethereum, ticker: "USDC", logo: "usdc", decimals: 6, priceProviderId: "usd-coin", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", isNativeToken: false)
        }
        static var baseEth: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        static var kujiraLVN: CoinMeta {
            CoinMeta(chain: Chain.kujira, ticker: "LVN", logo: "levana", decimals: 6, priceProviderId: "levana-protocol", contractAddress: "ibc/B64A07C006C0F5E260A8AD50BD53568F1FD4A0D75B7A9F8765C81BEAFDA62053", isNativeToken: false)
        }
        static var suiSUI: CoinMeta {
            CoinMeta(chain: Chain.sui, ticker: "SUI", logo: "sui", decimals: 9, priceProviderId: "sui", contractAddress: "", isNativeToken: true)
        }
        static var baseWewe: CoinMeta {
            CoinMeta(chain: Chain.base, ticker: "WEWE", logo: "wewe", decimals: 18, priceProviderId: "", contractAddress: "0x6b9bb36519538e0C073894E964E90172E1c0B41F", isNativeToken: false)
        }
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
        static var ethSepolia: CoinMeta {
            CoinMeta(chain: Chain.ethereumSepolia, ticker: "ETH", logo: "eth", decimals: 18, priceProviderId: "ethereum", contractAddress: "", isNativeToken: true)
        }
        static var mantle: CoinMeta {
            CoinMeta(chain: Chain.mantle, ticker: "MNT", logo: "mantle", decimals: 18, priceProviderId: "mantle", contractAddress: "", isNativeToken: true)
        }
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
