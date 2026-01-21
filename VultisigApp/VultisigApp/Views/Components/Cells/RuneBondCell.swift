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
        return convertedBond.formatForDisplay() + " RUNE"
    }

    var body: some View {
        HStack(spacing: 12) {
            logoView
            contentView
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
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
                .font(Theme.fonts.bodyLRegular)
                .foregroundColor(Theme.colors.textPrimary)

            Button(action: openExplorer) {
                Image(systemName: "link")
                    .font(Theme.fonts.bodyLRegular)
                    .foregroundColor(Theme.colors.textPrimary)
            }
            .padding(.leading, 4)

            Spacer()

            Text(bondValueInFiat)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }

    var detailsView: some View {
        HStack {
            Text(bondValueInRune)
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
            Spacer()
            Text(nodeStatus)
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(statusColor)
        }
    }

    private var statusColor: Color {
        switch bondNode.status.lowercased() {
        case "active":
            return Theme.colors.alertSuccess
        case "standby":
            return Theme.colors.alertWarning
        case "disabled":
            return Theme.colors.alertError
        default:
            return Theme.colors.textSecondary
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
