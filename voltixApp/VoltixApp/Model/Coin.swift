import Foundation
import SwiftData
import BigInt

class Coin: Codable, Hashable {
    let chain: Chain
    let ticker: String
    let logo: String
    var address: String
    let chainType: ChainType?
    
    @DecodableDefault.EmptyString var decimals: String
    @DecodableDefault.EmptyString var hexPublicKey: String
    @DecodableDefault.EmptyString var feeUnit: String
    @DecodableDefault.EmptyString var feeDefault: String
    @DecodableDefault.EmptyString var priceProviderId: String
    @DecodableDefault.EmptyString var contractAddress: String
    @DecodableDefault.EmptyString var rawBalance: String
    @DecodableDefault.False var isNativeToken: Bool
    @DecodableDefault.EmptyDouble var priceRate: Double
    
    init(
        chain: Chain,
        ticker: String,
        logo: String,
        address: String,
        priceRate: Double,
        chainType: ChainType?,
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
        return "\(balanceDecimal)"
    }
    
    func getMaxValue(_ fee: BigInt) -> Decimal {
        
        var totalFeeAdjusted = fee
        if chain.chainType == .EVM {
            let adjustmentFactor = BigInt(10).power(EVMHelper.ethDecimals - (Int(decimals) ?? 0))
            totalFeeAdjusted = fee / adjustmentFactor
        }
        
        let maxValue = (BigInt(rawBalance, radix: 10) ?? 0) - totalFeeAdjusted
        let maxValueDecimal = Decimal(string: String(maxValue)) ?? 0.0
        let tokenDecimals = Int(decimals) ?? 0
        return maxValueDecimal / pow(10, tokenDecimals)
    }

    var balanceInFiatDecimal: Decimal {
        let balanceInFiat = balanceDecimal * Decimal(priceRate)
        return balanceInFiat
    }
    
    var balanceInFiat: String {
        let balanceInFiat = balanceDecimal * Decimal(priceRate)
        return balanceInFiat.formatToFiat()
    }
    
    var swapAsset: String {
        guard !isNativeToken else { return "\(chain.swapAsset).\(chain.ticker)" }
        return "\(chain.swapAsset).\(ticker)-\(contractAddress)"
    }
    
    func toString() -> String {
        let properties = [
            "chain: \(chain.name)",
            "ticker: \(ticker)",
            "logo: \(logo)",
            "address: \(address)",
            "chainType: \((chainType?.description) ?? "N/A")",
            "decimals: \(decimals)",
            "hexPublicKey: \(hexPublicKey)",
            "feeUnit: \(feeUnit)",
            "feeDefault: \(feeDefault)",
            "priceProviderId: \(priceProviderId)",
            "contractAddress: \(contractAddress)",
            "rawBalance: \(rawBalance)",
            "isNativeToken: \(isNativeToken)",
            "priceRate: \(priceRate)",
            "balance: \(balanceString)",
            "balanceInFiat: \(balanceInFiat)",
            "swapAsset: \(swapAsset)"
        ]
        return properties.joined(separator: ",\n")
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
