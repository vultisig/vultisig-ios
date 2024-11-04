import SwiftUI

struct TokenSelectionCell: View {
    let chain: Chain
    let address: String
    let asset: TokenSelectionViewModel.Token
    let tokenSelectionViewModel: TokenSelectionViewModel
    
    @State var isSelected = false {
        didSet {
            handleSelection(isSelected)
        }
    }

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            image
            text
            Spacer()
            toggle
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .onAppear {
            setData()
        }
        .onTapGesture {
            isSelected.toggle()
        }
    }
    
    var image: some View {
        AsyncImageView(logo: asset.logo, size: CGSize(width: 32, height: 32), ticker: asset.symbol, tokenChainLogo: nil)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset.symbol)
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
    
    private func setData() {
        if coinSelectionViewModel.selection.contains(where: { $0.chain == chain && $0.ticker.lowercased() == asset.symbol.lowercased() }) {
            isSelected = true
        } else {
            isSelected = false
        }
    }
    
    private func handleSelection(_ isSelected: Bool) {
        coinSelectionViewModel.handleSelection(isSelected: isSelected, asset: convertToCoinMeta(asset))
    }
    
    private func convertToCoinMeta(_ asset: TokenSelectionViewModel.Token) -> CoinMeta {
        switch asset {
        case .coin(let coin):
            return coin
        case .oneInch(let token):
            return CoinMeta(
                chain: chain,
                ticker: token.symbol,
                logo: token.logoURI ?? .empty,
                decimals: token.decimals,
                priceProviderId: token.symbol.lowercased(),
                contractAddress: token.address,
                isNativeToken: false
            )
        }
    }
}
