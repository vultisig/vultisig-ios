import SwiftUI

struct TokenSelectionCell: View {
    let chain: Chain
    let address: String
    let asset: TokenSelectionViewModel.Token
    let tokenSelectionViewModel: TokenSelectionViewModel
    let tokenSelectionView: TokenSelectionView
    
    @State var isSelected = false
    
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
        .onChange(of: isSelected) { _, newValue in
            handleSelection(newValue)
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
        
        let existingCoin: Coin? = coinSelectionViewModel.selection.first(where: { $0.chain == chain && $0.ticker.lowercased() == asset.symbol.lowercased() })
        
        if let coin = existingCoin {
            coinSelectionViewModel.handleSelection(isSelected: isSelected, asset: coin)
        } else {
            coinSelectionViewModel.handleSelection(isSelected: isSelected, asset: convertToCoin(asset))
        }
        
        // Save assets whenever the selection changes
        Task {
            await coinSelectionViewModel.saveAssets(for: tokenSelectionView.vault)
        }
    }
    
    private func convertToCoin(_ asset: TokenSelectionViewModel.Token) -> Coin {
        switch asset {
        case .coin(let coin):
            return coin
        case .oneInch(let token):
            return Coin(
                chain: chain,
                ticker: token.symbol,
                logo: token.logoURI ?? .empty,
                address: address,
                priceRate: 0,
                decimals: token.decimals,
                hexPublicKey: .empty,
                priceProviderId: token.symbol.lowercased(),
                contractAddress: token.address,
                rawBalance: .zero,
                isNativeToken: false
            )
        }
    }
}
