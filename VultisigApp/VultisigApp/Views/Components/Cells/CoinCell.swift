import SwiftUI

struct CoinCell: View {
    @ObservedObject var coin: Coin
    @ObservedObject var group: GroupedChain
    let vault: Vault
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            logo
            content
        }
        .padding(16)
        .background(Color.blue600)
    }
    
    var logo: some View {
        AsyncImageView(logo: coin.logo, size: CGSize(width: 32, height: 32), ticker: coin.ticker, tokenChainLogo: coin.tokenChainLogo)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            quantity
        }
    }
    
    var header: some View {
        HStack {
            title
            Spacer()
            amount
        }
    }
    
    var title: some View {
        Text(coin.ticker)
            .font(.body20Menlo)
            .foregroundColor(.neutral0)
    }
    
    var quantity: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : coin.balanceString.formatCurrencyAbbreviation())
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .redacted(reason: coin.rawBalance.isEmpty ? .placeholder : [])
    }
    
    var amount: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : coin.balanceInFiat)
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .redacted(reason: coin.balanceInFiat.isEmpty ? .placeholder : [])
    }
}

#Preview {
    CoinCell(coin: Coin.example, group: GroupedChain.example, vault: Vault.example)
        .environmentObject(SettingsViewModel())
}
