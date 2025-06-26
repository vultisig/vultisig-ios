import SwiftUI

struct CoinCell: View {
    @ObservedObject var coin: Coin
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
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
            
            HStack {
                quantity
                if !coin.stakedBalance.isEmpty, coin.stakedBalance != .zero {
                    Spacer()
                    stakedAmount
                }
                
            }
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
        let displayBalance = homeViewModel.hideVaultBalance ? "****" : coin.balanceDecimal.formatForDisplay()
        
        return Text(displayBalance)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .redacted(reason: coin.rawBalance.isEmpty ? .placeholder : [])
    }
    
    var stakedAmount: some View {
        let formattedStakedBalance = coin.stakedBalanceDecimal.formatForDisplay()
        
        let labelText: String
        if coin.ticker.uppercased() == "TCY".uppercased() {
            labelText = "Staked"
        } else if coin.isNativeToken {
            labelText = "Bonded"
        } else {
            labelText = "Merged"
        }
        
        return Text(homeViewModel.hideVaultBalance ? "****" : "\(formattedStakedBalance) \(labelText)")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .redacted(reason: coin.stakedBalance.isEmpty ? .placeholder : [])
    }
    
    var amount: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : coin.balanceInFiat)
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .redacted(reason: coin.balanceInFiat.isEmpty ? .placeholder : [])
    }
}

#Preview {
    CoinCell(coin: Coin.example)
        .environmentObject(SettingsViewModel())
}
