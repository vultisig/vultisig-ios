import Foundation
import SwiftData
import BigInt

@Model
class Coin: ObservableObject, Codable, Hashable {
    var id: String
    var chain: Chain
    var address: String
    var hexPublicKey: String
    var ticker: String
    var contractAddress: String
    var isNativeToken: Bool
    
    @Attribute(originalName: "decimals") private(set) var strDecimals: String
    
    var logo: String
    var priceProviderId: String
    var rawBalance: String = ""
    var stakedBalance: String = ""
    
    @Transient var bondedNodes: [RuneBondNode] = []
    
    var decimals: Int {
        get {
            return Int(strDecimals) ?? 0
        }
        set {
            strDecimals = String(newValue)
        }
    }
    
    init(asset: CoinMeta, address: String, hexPublicKey: String) {
        self.chain = asset.chain
        self.ticker = asset.ticker
        self.logo = asset.logo
        self.strDecimals = String(asset.decimals)
        self.priceProviderId = asset.priceProviderId
        self.contractAddress = asset.contractAddress
        self.isNativeToken = asset.isNativeToken
        self.id = asset.coinId(address: address)
        
        self.rawBalance = .zero
        self.stakedBalance = .zero
        self.address = address
        self.hexPublicKey = hexPublicKey
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let chain = try container.decode(Chain.self, forKey: .chain)
        let ticker = try container.decode(String.self, forKey: .ticker)
        let address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        
        self.chain = chain
        self.ticker = ticker
        self.address = address
        self.logo = try container.decode(String.self, forKey: .logo)
        self.strDecimals = String(try container.decode(Int.self, forKey: .decimals))
        self.priceProviderId = try container.decode(String.self, forKey: .priceProviderId)
        self.contractAddress = try container.decode(String.self, forKey: .contractAddress)
        self.isNativeToken = try container.decode(Bool.self, forKey: .isNativeToken)
        self.hexPublicKey = try container.decodeIfPresent(String.self, forKey: .hexPublicKey) ?? ""
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(chain.rawValue)-\(ticker)-\(address)"
        
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(chain, forKey: .chain)
        try container.encode(ticker, forKey: .ticker)
        try container.encode(logo, forKey: .logo)
        try container.encode(decimals, forKey: .decimals)
        try container.encode(priceProviderId, forKey: .priceProviderId)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(isNativeToken, forKey: .isNativeToken)
        try container.encode(hexPublicKey, forKey: .hexPublicKey)
        try container.encode(address, forKey: .address)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Coin, rhs: Coin) -> Bool {
        return lhs.id == rhs.id
    }
    
    var balanceDecimal: Decimal {
        let value = rawBalance.toDecimal() / pow(10, decimals)
        return value
    }
    
    var stakedBalanceDecimal: Decimal {
        let value = stakedBalance.toDecimal() / pow(10, decimals)
        return value
    }
    var combinedBalanceDecimal: Decimal {
        let combined = balanceDecimal + stakedBalanceDecimal
        return combined
    }
    
    var balanceString: String {
        return balanceDecimal.formatToDecimal(digits: 8)
    }
    
    var balanceInFiat: String {
        return balanceInFiatDecimal.formatToFiat()
    }
    
    var chainType: ChainType {
        switch chain {
        case .thorChain,.mayaChain:
            return .THORChain
        case .solana:
            return .Solana
        case .ethereum,.avalanche,.base,.blast,.arbitrum,.polygon, .polygonV2,.optimism,.bscChain,.cronosChain, .zksync,.ethereumSepolia:
            return .EVM
        case .bitcoin,.bitcoinCash,.litecoin,.dogecoin,.dash, .zcash:
            return .UTXO
        case .cardano:
            return .Cardano
        case .gaiaChain,.kujira, .dydx, .osmosis, .terra, .terraClassic, .noble, .akash:
            return .Cosmos
        case .sui:
            return .Sui
        case .polkadot:
            return .Polkadot
        case .ton:
            return .Ton
        case .ripple:
            return .Ripple
        case .tron:
            return .Tron
        }
    }
    
    var supportsFeeSettings: Bool {
        switch chainType {
        case .EVM, .UTXO:
            return true
        default:
            return false
        }
    }
    
    var feeDefault: String{
        switch self.chain {
        case .thorChain:
            return "2000000"
        case .mayaChain:
            return "2000000000"
        case .solana:
            return SolanaHelper.defaultFeeInLamports.description
        case .ethereum,.avalanche, .bscChain,.ethereumSepolia:
            if self.isNativeToken {
                return "23000"
            } else {
                return "120000"
            }
        case .arbitrum:
            return "120000"
        case .base,.blast,.optimism,.cronosChain, .polygon, .polygonV2:
            if self.isNativeToken {
                return "40000"
            } else {
                return "120000"
            }
        case .zksync:
            return "200000"
        case .bitcoin,.bitcoinCash,.dash, .cardano:
            return "20"
        case .zcash:
            return "1000" // "2000" for faster confirmation
        case .litecoin:
            return "1000"
        case .dogecoin:
            return "1000000"
        case .noble:
            return "200000"
        case .terraClassic:
            return "100000000"
        case .terra:
            return "7500"
        case .kujira:
            return "7500"
        case .osmosis:
            return "7500"
        case .gaiaChain:
            return "7500"
        case .dydx:
            return DydxHelper.DydxGasLimit.description
        case .sui:
            return "3000000"
        case .polkadot:
            return "250000000" // 0.025
        case .ton:
            return TonHelper.defaultFee.description
        case .ripple:
            return "180000"
        case .akash:
            return "3000" // 0.003 AKT Cosmos station uses something like that
        case .tron:
            return "800000"
        }
    }
    
    var price: Double {
        return RateProvider.shared.rate(for: self)?.value ?? 0
    }
    
    func decimal(for value: BigInt) -> Decimal {
        let decimalValue = value.description.toDecimal()
        return decimalValue / pow(Decimal(10), decimals)
    }
    
    func raw(for value: Decimal) -> BigInt {
        var decimal = value * pow(10, decimals)
        
        var result = Decimal()
        NSDecimalRound(&result, &decimal, 0,.up)
        return BigInt(result.description) ?? BigInt(0)
    }
    
    func fiat(value: BigInt) -> Decimal {
        let decimal = decimal(for: value)
        return RateProvider.shared.fiatBalance(value: decimal, coin: self)
    }
    
    func fiat(decimal: Decimal) -> Decimal {
        return RateProvider.shared.fiatBalance(value: decimal, coin: self)
    }
    
    var swapAsset: String {
        guard !isNativeToken else {
            if chain == .gaiaChain {
                return "\(chain.swapAsset).ATOM"
            }
            if chain == .kujira {
                return "\(chain.swapAsset).KUJI"
            }
            if chain == .arbitrum || chain == .base {
                return "\(chain.swapAsset).ETH"
            }
            return "\(chain.swapAsset).\(chain.ticker)"
        }

        if chain == .thorChain {
            return "\(chain.swapAsset).\(ticker)"
        }

        return "\(chain.swapAsset).\(ticker)-\(contractAddress)"
    }
    
    func getMaxValue(_ fee: BigInt) -> Decimal {
        let totalFeeAdjusted = fee
        let maxValue = rawBalance.toBigInt() - totalFeeAdjusted
        let maxValueDecimal = maxValue.toDecimal(decimals: decimals)
        let tokenDecimals = decimals
        let maxValueCalculated = maxValueDecimal / pow(10, tokenDecimals)
        
        return maxValueCalculated < .zero ? 0 : maxValueCalculated.truncated(toPlaces: decimals - 1)
    }
    
    var balanceInFiatDecimal: Decimal {
        let combined = combinedBalanceDecimal
        let fiat = RateProvider.shared.fiatBalance(value: combined, coin: self)
        return fiat
    }
    
    var blockchairKey: String {
        return "\(address)-\(chain.name.lowercased())"
    }
    
    var shouldApprove: Bool {
        return !isNativeToken && chain.chainType == .EVM
    }
    
    
    
    var tokenChainLogo: String? {
        guard chain.logo != logo else { return nil }
        return chain.logo
    }
    

    var isRune: Bool {
        return chain == .thorChain && ticker.uppercased() == "RUNE" && isNativeToken
    }
     
    var hasBondedNodes: Bool {
        return !bondedNodes.isEmpty
    }
    
    static let example: Coin = {
        let asset = CoinMeta(chain: .bitcoin, ticker: "BTC", logo: "BitcoinLogo", decimals: 8, priceProviderId: "Bitcoin", contractAddress: "ContractAddressExample", isNativeToken: false)
        return Coin(asset: asset, address: "bc1qxyzbc1qxyzbc1qxyzbc1qxyzbc1qxyzbc1qxyzbc1qxyzbc1qxyz", hexPublicKey: "HexPublicKeyExample")
    }()
    
    func toCoinMeta() -> CoinMeta {
        return CoinMeta(chain: chain, ticker: ticker, logo: logo, decimals: decimals, priceProviderId: priceProviderId, contractAddress: contractAddress, isNativeToken: isNativeToken)
    }
}

extension Coin: Comparable {
    
    static func < (lhs: Coin, rhs: Coin) -> Bool {
        if lhs.balanceInFiatDecimal != rhs.balanceInFiatDecimal {
            return lhs.balanceInFiatDecimal > rhs.balanceInFiatDecimal
        }
        else if lhs.chain.name != rhs.chain.name {
            return lhs.chain.name < rhs.chain.name
        }
        else if lhs.isNativeToken != rhs.isNativeToken {
            return !lhs.isNativeToken
        }
        else {
            return lhs.ticker < rhs.ticker
        }
    }
}

private extension Coin {
    enum CodingKeys: String, CodingKey {
        case id
        case chain
        case ticker
        case logo
        case chainType
        case decimals
        case feeDefault
        case priceProviderId
        case contractAddress
        case isNativeToken
        case hexPublicKey
        case address
    }
}
