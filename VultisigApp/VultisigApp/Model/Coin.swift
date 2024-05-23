import Foundation
import SwiftData
import BigInt

@Model
class Coin: ObservableObject, Codable, Hashable {
    @Attribute(.unique) var id: String

    let chain: Chain
    let ticker: String
    let logo: String
    let chainType: ChainType
    let decimals: String
    let feeUnit: String
    let feeDefault: String
    let contractAddress: String
    let isNativeToken: Bool

    var priceProviderId: String

    var hexPublicKey: String = ""
    var address: String = ""
    var rawBalance: String = ""
    var priceRate: Double = 0

    @Relationship var vault: Vault?

    init(
        chain: Chain,
        ticker: String,
        logo: String,
        address: String,
        priceRate: Double,
        chainType: ChainType,
        decimals: String,
        hexPublicKey: String,
        feeUnit: String,
        priceProviderId: String,
        contractAddress: String,
        rawBalance: String,
        isNativeToken: Bool,
        feeDefault: String
    ) {
        self.chain = chain
        self.ticker = ticker
        self.logo = logo
        self.address = address
        self.priceRate = priceRate
        self.chainType = chainType
        self.decimals = decimals
        self.hexPublicKey = hexPublicKey
        self.feeUnit = feeUnit
        self.priceProviderId = priceProviderId
        self.contractAddress = contractAddress
        self.rawBalance = rawBalance
        self.isNativeToken = isNativeToken
        self.feeDefault = feeDefault

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
        self.chainType = try container.decode(ChainType.self, forKey: .chainType)
        self.decimals = try container.decode(String.self, forKey: .decimals)
        self.feeUnit = try container.decode(String.self, forKey: .feeUnit)
        self.feeDefault = try container.decode(String.self, forKey: .feeDefault)
        self.priceProviderId = try container.decode(String.self, forKey: .priceProviderId)
        self.contractAddress = try container.decode(String.self, forKey: .contractAddress)
        self.isNativeToken = try container.decode(Bool.self, forKey: .isNativeToken)
        self.hexPublicKey = try container.decodeIfPresent(String.self, forKey: .hexPublicKey) ?? ""
        self.rawBalance = try container.decodeIfPresent(String.self, forKey: .rawBalance) ?? ""
        self.priceRate = try container.decodeIfPresent(Double.self, forKey: .priceRate) ?? 0

        self.id = "\(chain.rawValue)-\(ticker)-\(address)"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(ticker, forKey: .ticker)
        try container.encode(logo, forKey: .logo)
        try container.encode(chainType, forKey: .chainType)
        try container.encode(decimals, forKey: .decimals)
        try container.encode(feeUnit, forKey: .feeUnit)
        try container.encode(feeDefault, forKey: .feeDefault)
        try container.encode(priceProviderId, forKey: .priceProviderId)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(isNativeToken, forKey: .isNativeToken)
        try container.encode(hexPublicKey, forKey: .hexPublicKey)
        try container.encode(address, forKey: .address)
        try container.encode(rawBalance, forKey: .rawBalance)
        try container.encode(priceRate, forKey: .priceRate)
    }


    func clone() -> Coin {
        return Coin(
            chain: chain,
            ticker: ticker,
            logo: logo,
            address: address,
            priceRate: priceRate,
            chainType: chainType,
            decimals: decimals,
            hexPublicKey: hexPublicKey,
            feeUnit: feeUnit,
            priceProviderId: priceProviderId,
            contractAddress: contractAddress,
            rawBalance: rawBalance,
            isNativeToken: isNativeToken,
            feeDefault: feeDefault
        )
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ticker)
        hasher.combine(address)
        hasher.combine(chain.name)
    }
    
    static func == (lhs: Coin, rhs: Coin) -> Bool {
        return lhs.ticker == rhs.ticker && lhs.address == rhs.address && lhs.chain.name == rhs.chain.name
    }
    
    
    var balanceDecimal: Decimal {
        let tokenBalance = Decimal(string: rawBalance) ?? 0.0
        let tokenDecimals = Int(decimals) ?? 0
        return tokenBalance / pow(10, tokenDecimals)
    }
    
    var balanceString: String {
        return balanceDecimal.formatToDecimal(digits: 4)
    }
    
    var balanceInFiat: String {
        let balanceInFiat = balanceDecimal * Decimal(priceRate)
        return balanceInFiat.formatToFiat()
    }

    func decimal(for value: BigInt) -> Decimal {
        let decimals = Int(decimals) ?? 0
        let decimalValue = Decimal(string: String(value)) ?? 0
        return decimalValue / pow(Decimal(10), decimals)
    }

    func raw(for value: Decimal) -> BigInt {
        let tokenDecimals = Int(decimals) ?? 0
        let decimal = value * pow(10, tokenDecimals)
        return BigInt(decimal.description) ?? BigInt.zero
    }

    func fiat(for value: BigInt) -> Decimal {
        let decimal = decimal(for: value)
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
            let adjustmentFactor = BigInt(10).power(EVMHelper.ethDecimals - (Int(decimals) ?? 0))
            totalFeeAdjusted = fee / adjustmentFactor
        }
        
        let maxValue = (BigInt(rawBalance, radix: 10) ?? .zero) - totalFeeAdjusted
        let maxValueDecimal = Decimal(string: String(maxValue)) ?? .zero
        let tokenDecimals = Int(decimals) ?? .zero
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
        chainType: ChainType.UTXO,
        decimals: "8",
        hexPublicKey: "HexPublicKeyExample",
        feeUnit: "Satoshi",
        priceProviderId: "Bitcoin",
        contractAddress: "ContractAddressExample",
        rawBalance: "500000000",
        isNativeToken: false,
        feeDefault: "20"
    )
}

private extension Coin {

    enum CodingKeys: String, CodingKey {
         case chain
         case ticker
         case logo
         case chainType
         case decimals
         case feeUnit
         case feeDefault
         case priceProviderId
         case contractAddress
         case isNativeToken
         case hexPublicKey
         case address
         case rawBalance
         case priceRate
     }
}
