import SwiftUI

struct TokenSelectionCell: View {
    let chain: Chain
    let address: String
    let asset: CoinMeta
    
    @Binding var isSelected: Bool
    
    var body: some View {
        ZStack {
            Theme.colors.bgSurface1
                .cornerRadius(10)
                .onTapGesture {
                    isSelected.toggle()
                }

            HStack(spacing: 16) {
                Group {
                    image
                    text
                    Spacer()
                }
                toggle
            }
            .frame(height: 72)
            .padding(.horizontal, 16)
        }
    }
    
    var image: some View {
        AsyncImageView(logo: asset.logo, size: CGSize(width: 32, height: 32), ticker: asset.ticker, tokenChainLogo: nil)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset.ticker)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(chain.name)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    var toggle: some View {
        container
    }
    
    var content: some View {
        Toggle("Is selected", isOn: $isSelected)
            .labelsHidden()
            .scaleEffect(0.6)
    }
}
