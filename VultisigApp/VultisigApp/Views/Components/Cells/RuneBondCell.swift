import SwiftUI

struct RuneBondCell: View {
    @Environment(\.openURL) private var openURL
    let bondNode: RuneBondNode
    let coin: Coin
    
    private var nodeIdentifier: String {
        return bondNode.shortAddress.lowercased()
    }
    
    private var nodeStatus: String {
        return "(\(bondNode.status))"
    }
    
    private var bondValueInFiat: String {
        // Convert from base units (divide by 1e8) then calculate fiat value
        let bondDecimal = convertFromBaseUnits(bondNode.bond)
        return RateProvider.shared.fiatBalance(value: bondDecimal, coin: coin).formatToFiat()
    }
    
    private var bondValueInRune: String {
        // Convert from base units (divide by 1e8) and format with appropriate digits
        let convertedBond = convertFromBaseUnits(bondNode.bond)
        return convertedBond.formatToDecimal(digits: 8) + " RUNE"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(nodeIdentifier)
                    .font(.body20Menlo)
                    .foregroundColor(.neutral0)
                
                Text(nodeStatus)
                    .font(.body16Menlo)
                    .foregroundColor(statusColor)
                
                Spacer()
                
                Text(bondValueInFiat)
                    .font(.body16MenloBold)
                    .foregroundColor(.neutral0)
                
                Button(action: openExplorer) {
                    Image(systemName: "link")
                        .font(.body18Menlo)
                        .foregroundColor(.neutral0)
                }
                .padding(.leading, 8)
            }
            
            HStack {
                Text(bondNode.address)
                    .font(.body12Menlo)
                    .foregroundColor(.neutral400)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Text(bondValueInRune)
                    .font(.body12Menlo)
                    .foregroundColor(.neutral0)
            }
        }
        .padding(16)
        .background(Color.blue800)
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch bondNode.status.lowercased() {
        case "active":
            return .reshareCellGreen
        case "standby":
            return .alertYellow
        case "disabled":
            return .alertRed
        default:
            return .neutral400
        }
    }
    
    /// Converts a value from base units to display units
    private func convertFromBaseUnits(_ value: Decimal) -> Decimal {
        // Convert using the same approach as in Coin.balanceDecimal
        return value / Foundation.pow(10, coin.decimals)
    }
    
    /// Opens the THORChain explorer to view node details
    private func openExplorer() {
        if let explorerURLString = Endpoint.getExplorerByAddressURLByGroup(chain: .thorChain, address: bondNode.address),
           let url = URL(string: explorerURLString) {
            openURL(url)
        }
    }
}

#Preview {
    let bondNode = RuneBondNode(
        status: "Active",
        address: "thor1abcdefghijklmnopqrstuvwxyz123456789",
        bond: Decimal(string: "10000.0")!
    )
    
    let asset = CoinMeta(
        chain: .thorChain,
        ticker: "RUNE",
        logo: "RuneLogo",
        decimals: 8,
        priceProviderId: "RUNE",
        contractAddress: "",
        isNativeToken: true
    )
    
    let coin = Coin(asset: asset, address: "thor1abcdefghijklmnopqrstuvwxyz123456789", hexPublicKey: "")
    
    return RuneBondCell(bondNode: bondNode, coin: coin)
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.blue600)
}
