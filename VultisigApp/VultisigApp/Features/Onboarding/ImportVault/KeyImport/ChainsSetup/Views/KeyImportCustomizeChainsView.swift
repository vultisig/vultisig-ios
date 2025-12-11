//
//  KeyImportCustomizeChainsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import SwiftUI

struct KeyImportCustomizeChainsView: View {
    @ObservedObject var viewModel: KeyImportChainsSetupViewModel
    let onImport: () -> Void
    
    @State var expandOtherChains = false
    
    var body: some View {
        VStack(spacing: 16) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    activeChainsView
                    addOtherChainsView
                        .showIf(!viewModel.activeChains.isEmpty)
                }
            }
            PrimaryButton(title: viewModel.buttonTitle, action: onImport)
                .disabled(viewModel.buttonDisabled)
        }
    }
    
    @ViewBuilder
    var activeChainsView: some View {
        let chains = viewModel.activeChains.isEmpty ? viewModel.otherChains : viewModel.activeChains
        VStack(alignment: .leading, spacing: 8) {
            Text("customizeChains")
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            HStack {
                Text(String(format: "selectChainsToImport".localized, viewModel.maxChains))
                    .foregroundStyle(Theme.colors.textExtraLight)
                Spacer()
                Text("(\(viewModel.selectedChainsCount)/\(viewModel.maxChains))")
                    .foregroundStyle(viewModel.maxChainsExceeded ? Theme.colors.alertError : Theme.colors.textExtraLight)
            }
            .font(Theme.fonts.bodySMedium)
        }
        
        VStack(spacing: 0) {
            ForEach(Array(chains.enumerated()), id: \.element) { offset, chain in
                cell(for: chain, offset: offset, chainsCount: chains.count)
            }
        }
    }
    
    @ViewBuilder
    var addOtherChainsView: some View {
        ExpandableView(isExpanded: $expandOtherChains) {
            Button {
                withAnimation(.interpolatingSpring) {
                    expandOtherChains.toggle()
                }
            } label: {
                HStack {
                    Text("addOtherChains")
                        .foregroundStyle(Theme.colors.textExtraLight)
                        .font(Theme.fonts.footnote)
                    Spacer()
                    Icon(named: "chevron-down-small", color: Theme.colors.textPrimary, size: 16)
                        .rotationEffect(.degrees(expandOtherChains ? 180 : 0))
                }
                .padding(.bottom, 20)
            }
            .contentShape(Rectangle())
        } content: {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.otherChains.enumerated()), id: \.element) { offset, chain in
                    cell(for: chain, offset: offset, chainsCount: viewModel.otherChains.count)
                }
            }
        }
    }
    
    func cell(for chain: KeyImportChain, offset: Int, chainsCount: Int) -> some View {
        KeyImportChainView(
            chain: chain,
            isSelected: Binding(get: {
                viewModel.isSelected(chain: chain)
            }, set: {
                viewModel.toggleSelection(chain: chain, isSelected: $0)
            })
        ).commonListItemContainer(index: offset, itemsCount: chainsCount)
    }
}

struct KeyImportChainView: View {
    let chain: KeyImportChain
    @Binding var isSelected: Bool
    
    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: chain.chain.logo,
                    size: .init(width: 32, height: 32),
                    ticker: "",
                    tokenChainLogo: nil
                )
                Text(chain.chain.name)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
                Spacer()
                Text(chain.balance)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.priceBodyS)
                Checkbox(isChecked: $isSelected, isExtended: false)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.colors.bgSecondary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    KeyImportCustomizeChainsView(
        viewModel: KeyImportChainsSetupViewModel(),
        onImport: {}
    )
}
