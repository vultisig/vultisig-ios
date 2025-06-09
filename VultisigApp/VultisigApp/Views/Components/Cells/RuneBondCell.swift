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
        let bondDecimal = convertFromBaseUnits(bondNode.bond)
        return RateProvider.shared.fiatBalance(value: bondDecimal, coin: coin).formatToFiat()
    }
    
    private var bondValueInRune: String {
        let convertedBond = convertFromBaseUnits(bondNode.bond)
        return convertedBond.formatToDecimal(digits: 8) + " RUNE"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            logoView
            contentView
        }
        .padding(16)
        .background(Color.blue600)
    }
    
    var logoView: some View {
        AsyncImageView(logo: coin.logo, size: CGSize(width: 32, height: 32), ticker: coin.ticker, tokenChainLogo: coin.tokenChainLogo)
    }

    var contentView: some View {
        VStack(alignment: .leading, spacing: 15) { 
            headerView
            detailsView
        }
    }

    var headerView: some View {
        HStack {
            Text(nodeIdentifier)
                .font(.body20Menlo)
                .foregroundColor(.neutral0)
            
            Button(action: openExplorer) {
                Image(systemName: "link")
                    .font(.body18Menlo) 
                    .foregroundColor(.neutral0)
            }
            .padding(.leading, 4) 
            
            Spacer()
            
            Text(bondValueInFiat)
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
        }
    }

    var detailsView: some View {
        HStack {
            Text(bondValueInRune)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            Spacer()
            Text(nodeStatus)
                .font(.body16Menlo)
                .foregroundColor(statusColor) 
        }
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
    
    private func convertFromBaseUnits(_ value: Decimal) -> Decimal {
        return value / Foundation.pow(10, coin.decimals)
    }
    
    private func openExplorer() {
        let explorerURLString = Endpoint.thorchainNodeExplorerURL(bondNode.address)
        if let url = URL(string: explorerURLString) {
            openURL(url)
        }
    }
}

