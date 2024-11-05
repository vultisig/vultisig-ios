import SwiftUI

struct TokenSelectionCell: View {
    let chain: Chain
    let address: String
    let asset: CoinMeta
    
    @Binding var isSelected: Bool
    
    var body: some View {
        ZStack {
            Color.blue600
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
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)
            
            Text(chain.name)
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
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
