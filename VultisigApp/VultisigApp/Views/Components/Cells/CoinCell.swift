import SwiftUI

struct CoinCell: View {
    @ObservedObject var coin: Coin
    
    let group: GroupedChain
    let vault: Vault
    
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
            amount
        }
    }
    
    var header: some View {
        HStack {
            title
            Spacer()
            quantity
        }
    }
    
    var title: some View {
        Text(coin.ticker)
            .font(.body20Menlo)
            .foregroundColor(.neutral0)
    }
    
    var quantity: some View {
        Text(coin.balanceString)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .redacted(reason: coin.rawBalance.isEmpty ? .placeholder : [])
    }
    
    var amount: some View {
        Text(coin.balanceInFiat)
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .redacted(reason: coin.balanceInFiat.isEmpty ? .placeholder : [])
    }
}

#Preview {
    CoinCell(coin: Coin.example, group: GroupedChain.example, vault: Vault.example)
}
