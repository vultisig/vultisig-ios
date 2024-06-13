import Foundation
import SwiftData
import BigInt

@Model
class Coin: ObservableObject, Codable, Hashable {
    @Attribute(.unique) var id: String
    let chain: Chain
    let ticker: String
    var logo: String
    @Attribute(originalName: "decimals") var strDecimals: String
    let contractAddress: String
    let isNativeToken: Bool
    var priceProviderId: String
    var hexPublicKey: String = ""
    var address: String = ""
    var rawBalance: String = ""
    var priceRate: Double = 0
    
    var decimals: Int{
        get{
            return Int(strDecimals) ?? 0
        }
        set{
            strDecimals = String(newValue)
        }
    }
    init(
        chain: Chain,
        ticker: String,
        logo: String,
        address: String,
        priceRate: Double,
        decimals: Int,
        hexPublicKey: String,
        priceProviderId: String,
        contractAddress: String,
        rawBalance: String,
        isNativeToken: Bool
    ) {
        self.chain = chain
        self.ticker = ticker
        self.logo = logo
        self.address = address
        self.priceRate = priceRate
        self.strDecimals = String(decimals)
        self.hexPublicKey = hexPublicKey
        self.priceProviderId = priceProviderId
        self.contractAddress = contractAddress
        self.rawBalance = rawBalance
        self.isNativeToken = isNativeToken
        
        self.id = "\(chain.rawValue)-\(ticker)-\(address)"
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
    
    
    func clone() -> Coin {
        return Coin(
            chain: chain,
            ticker: ticker,
            logo: logo,
            address: address,
            priceRate: priceRate,
            decimals: decimals,
            hexPublicKey: hexPublicKey,
            priceProviderId: priceProviderId,
            contractAddress: contractAddress,
            rawBalance: rawBalance,
            isNativeToken: isNativeToken
        )
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Coin, rhs: Coin) -> Bool {
        return lhs.id == rhs.id
    }
    
    var balanceDecimal: Decimal {
        let tokenBalance = Decimal(string: rawBalance) ?? 0.0
        let tokenDecimals = decimals
        return tokenBalance / pow(10, tokenDecimals)
    }
    
    var balanceString: String {
        return balanceDecimal.formatToDecimal(digits: 4)
    }
    
    var balanceInFiat: String {
        let balanceInFiat = balanceDecimal * Decimal(priceRate)
        return balanceInFiat.formatToFiat()
    }
    
    var chainType: ChainType {
        switch self.chain {
        case .thorChain,.mayaChain:
            return .THORChain
        case .solana:
            return .Solana
        case .ethereum,.avalanche,.base,.blast,.arbitrum,.polygon,.optimism,.bscChain,.cronosChain, .zksync:
            return .EVM
        case .bitcoin,.bitcoinCash,.litecoin,.dogecoin,.dash:
            return .UTXO
        case .gaiaChain,.kujira, .dydx:
            return .Cosmos
        case .sui:
            return .Sui
        case .polkadot:
            return .Polkadot
        }
    }
    var feeDefault: String{
        switch self.chain {
        case .thorChain:
            return "2000000"
        case .mayaChain:
            return "2000000000"
        case .solana:
            return "7000"
        case .ethereum,.avalanche,.base,.blast,.arbitrum,.polygon,.optimism,.bscChain,.cronosChain, .zksync:
            if self.isNativeToken {
                return "23000"
            } else {
                return "120000"
            }
        case .bitcoin,.bitcoinCash,.dash:
            return "20"
        case .litecoin:
            return "1000"
        case .dogecoin:
            return "1000000"
        case .gaiaChain,.kujira:
            return "200000"
        case .dydx:
            return DydxHelper.DydxGasLimit.description
        case .sui:
            return "500000000"
        case .polkadot:
            return "10000000000"
        }
    }
    
    func decimal(for value: BigInt) -> Decimal {
        let decimalValue = Decimal(string: String(value)) ?? 0
        return decimalValue / pow(Decimal(10), decimals)
    }
    
    func raw(for value: Decimal) -> BigInt {
        let decimal = value * pow(10, decimals)
        return BigInt(decimal.description) ?? BigInt.zero
    }
    
    func fiat(value: BigInt) -> Decimal {
        let decimal = decimal(for: value)
        return decimal * Decimal(priceRate)
    }
    
    func fiat(decimal: Decimal) -> Decimal {
        return decimal * Decimal(priceRate)
    }
    
    var swapAsset: String {
        guard !isNativeToken else {
            if chain == .gaiaChain {
                return "\(chain.swapAsset).ATOM"
            }
            return "\(chain.swapAsset).\(chain.ticker)"
        }
        return "\(chain.swapAsset).\(ticker)-\(contractAddress)"
    }
    
    func getMaxValue(_ fee: BigInt) -> Decimal {
        var totalFeeAdjusted = fee
        if chain.chainType == .EVM {
            let adjustmentFactor = BigInt(10).power(EVMHelper.ethDecimals - decimals)
            totalFeeAdjusted = fee / adjustmentFactor
        }
        
        let maxValue = (BigInt(rawBalance, radix: 10) ?? .zero) - totalFeeAdjusted
        let maxValueDecimal = Decimal(string: String(maxValue)) ?? .zero
        let tokenDecimals = decimals
        let maxValueCalculated = maxValueDecimal / pow(10, tokenDecimals)
        
        return maxValueCalculated < .zero ? 0 : maxValueCalculated
    }
    
    var balanceInFiatDecimal: Decimal {
        let balanceInFiat = balanceDecimal * Decimal(priceRate)
        return balanceInFiat
    }
    
    var blockchairKey: String {
        return "\(address)-\(chain.name.lowercased())"
    }
    
    var shouldApprove: Bool {
        return !isNativeToken && chain.chainType == .EVM
    }
    
    var tokenSchema: String? {
        guard !isNativeToken else { return nil }
        switch chain {
        case .ethereum:
            return "ERC20"
        case .bscChain:
            return "BEP20"
        default:
            return nil
        }
    }
    
    var tokenChainLogo: String? {
        guard !isNativeToken else { return nil }
        return chain.logo
    }
    
    static let example = Coin(
        chain: Chain.bitcoin,
        ticker: "BTC",
        logo: "BitcoinLogo",
        address: "bc1qxyz...",
        priceRate: 20000.0,
        decimals: 8,
        hexPublicKey: "HexPublicKeyExample",
        priceProviderId: "Bitcoin",
        contractAddress: "ContractAddressExample",
        rawBalance: "500000000",
        isNativeToken: false
    )
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
