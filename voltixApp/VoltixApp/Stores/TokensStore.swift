import Foundation

class TokensStore {
    static var TokenSelectionAssets = [
        Coin(chain: Chain.Bitcoin, ticker: "BTC", logo: "btc", address: "", priceRate: 0.0, chainType: ChainType.UTXO, decimals: "8", hexPublicKey: "", feeUnit: "Sats/vbyte", priceProviderId: "bitcoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "20"),
        
        Coin(chain: Chain.BitcoinCash, ticker: "BCH", logo: "bch", address: "", priceRate: 0.0, chainType: ChainType.UTXO, decimals: "8", hexPublicKey: "", feeUnit: "Sats/vbyte", priceProviderId: "bitcoin-cash", contractAddress: "", rawBalance: "0", isNativeToken: false, feeDefault: "20"),
        
        Coin(chain: Chain.Litecoin, ticker: "LTC", logo: "ltc", address: "", priceRate: 0.0, chainType: ChainType.UTXO, decimals: "8", hexPublicKey: "", feeUnit: "Lits/vbyte", priceProviderId: "litecoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "1000"),
        
        Coin(chain: Chain.Dogecoin, ticker: "DOGE", logo: "doge", address: "", priceRate: 0.0, chainType: ChainType.UTXO, decimals: "8", hexPublicKey: "", feeUnit: "Doges/vbyte", priceProviderId: "dogecoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "1000000"),
        
        Coin(chain: Chain.THORChain, ticker: "RUNE", logo: "rune", address: "", priceRate: 0.0, chainType: ChainType.THORChain, decimals: "8", hexPublicKey: "", feeUnit: "Rune", priceProviderId: "thorchain", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "0.02"),
        
        Coin(chain: Chain.Ethereum, ticker: "ETH", logo: "eth", address: "", priceRate: 0.0, chainType: ChainType.EVM, decimals: "18", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "ethereum", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "21000"),
        
        Coin(chain: Chain.Ethereum, ticker: "USDC", logo: "usdc", address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", priceRate: 1.0, chainType: ChainType.EVM, decimals: "6", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "usd-coin", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.Ethereum, ticker: "USDT", logo: "usdt", address: "0xdac17f958d2ee523a2206206994597c13d831ec7", priceRate: 1.0, chainType: ChainType.EVM, decimals: "6", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "tether", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.Ethereum, ticker: "UNI", logo: "uni", address: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", priceRate: 0.0, chainType: ChainType.EVM, decimals: "18", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "uniswap", contractAddress: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.Ethereum, ticker: "MATIC", logo: "matic", address: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", priceRate: 0.0, chainType: ChainType.EVM, decimals: "18", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "polygon", contractAddress: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.Ethereum, ticker: "WBTC", logo: "wbtc", address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", priceRate: 0.0, chainType: ChainType.EVM, decimals: "8", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "wrapped-bitcoin", contractAddress: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.Ethereum, ticker: "LINK", logo: "link", address: "0x514910771af9ca656af840dff83e8264ecf986ca", priceRate: 0.0, chainType: ChainType.EVM, decimals: "18", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "chainlink", contractAddress: "0x514910771af9ca656af840dff83e8264ecf986ca", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.Ethereum, ticker: "FLIP", logo: "flip", address: "0x826180541412d574cf1336d22c0c0a287822678a", priceRate: 0.0, chainType: ChainType.EVM, decimals: "18", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "chainflip", contractAddress: "0x826180541412d574cf1336d22c0c0a287822678a", rawBalance: "0", isNativeToken: false, feeDefault: "120000"),
        
        Coin(chain: Chain.Solana, ticker: "SOL", logo: "solana", address: "", priceRate: 0.0, chainType: ChainType.Solana, decimals: "9", hexPublicKey: "", feeUnit: "Lamports", priceProviderId: "solana", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "7000"),
        Coin(chain: Chain.Avalache, ticker: "AVAX", logo: "avax", address: "", priceRate: 0.0, chainType: ChainType.EVM, decimals: "18", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "avalanche", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "21000"),
        Coin(chain: Chain.BSCChain, ticker: "BNB", logo: "bsc", address: "", priceRate: 0.0, chainType: ChainType.EVM, decimals: "18", hexPublicKey: "", feeUnit: "Gwei", priceProviderId: "binancecoin", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "21000"),
        Coin(chain: Chain.GaiaChain, ticker: "ATOM", logo: "atom", address: "", priceRate: 0.0, chainType: ChainType.Cosmos, decimals: "6", hexPublicKey: "", feeUnit: "uatom", priceProviderId: "cosmos", contractAddress: "", rawBalance: "0", isNativeToken: true, feeDefault: "200000"),
    ]
    
    static func getCoin(_ ticker: String) -> Coin? {
        return TokenSelectionAssets.first(where: { $0.ticker == ticker}) ?? nil
    }
    
    static func createNewCoinInstance(ticker: String, address: String, hexPublicKey: String) -> Result<Coin, Error> {
        guard let templateCoin = getCoin(ticker) else {
            return .failure(HelperError.runtimeError("doesn't support coin \(ticker)"))
        }
        let clonedCoin = templateCoin.clone()
        clonedCoin.address = address
        clonedCoin.hexPublicKey = hexPublicKey
        return .success(clonedCoin)
    }
}
