//
//  VaultSelectChainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct VaultSelectChainScreen: View {
    let vault: Vault
    @Binding var isPresented: Bool
    @State var searchBarFocused: Bool = false
        
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    var body: some View {
        NavigationStack {
            container {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 24) {
                        textfield
                        Group {
                            if viewModel.searchText.isNotEmpty && viewModel.filteredChains.isEmpty {
                                emptyChainsView
                            } else {
                                ScrollView(showsIndicators: false) {
                                    chainsGrid
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .transition(.opacity)
                        .animation(.easeInOut, value: viewModel.searchText)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 16)
                    
                    gradientOverlay
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .presentationDetents([.large])
            .presentationBackground(Theme.colors.bgPrimary)
            .presentationDragIndicator(.visible)
            .onLoad {
                viewModel.setData(for: vault)
            }
        }
    }
    
    var gradientOverlay: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.5, y: 1),
            endPoint: UnitPoint(x: 0.5, y: 0)
        )
        .frame(height: 60)
    }
    
    var textfield: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("selectChains".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title2)
            
            HStack(spacing: 12) {
                SearchTextField(value: $viewModel.searchText, isFocused: $searchBarFocused)
                
                Button {
                    viewModel.searchText = ""
                    searchBarFocused.toggle()
                } label: {
                    Text("cancel".localized)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodySMedium)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .showIf(searchBarFocused)
            }
            .animation(.easeInOut, value: searchBarFocused)
        }
    }
    
    @ViewBuilder
    var chainsGrid: some View {
        let spacing: CGFloat = 16
        let gridItem = GridItem(.flexible(), spacing: spacing)
        LazyVGrid(
            columns: Array.init(repeating: gridItem, count: 4),
            spacing: spacing
        ) {
            ForEach(viewModel.filteredChains, id: \.self) { key in
                ChainGridCell(
                    assets: viewModel.groupedAssets[key] ?? [],
                    onSelection: onSelection
                )
            }
        }
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity)
    }
    
    var emptyChainsView: some View {
        VStack {
            VStack(spacing: 12) {
                Icon(named: "crypto", color: Theme.colors.primaryAccent4, size: 24)
                Text("noChainsFound")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSecondary))
            Spacer()
        }
    }
    
    var closeButton: some View {
        ToolbarButton(image: "xmark", type: .secondary) {
            isPresented.toggle()
        }
    }
    
    var saveButton: some View {
        ToolbarButton(image: "checkmark") {
            Task {
                await saveAssets()
            }
            isPresented.toggle()
        }
    }
    
    func onSelection(_ chainSelection: ChainSelection) {
        viewModel.handleSelection(isSelected: chainSelection.selected, asset: chainSelection.asset)
    }
    
    private func saveAssets() async {
        await CoinService.saveAssets(for: vault, selection: viewModel.selection)
    }
}

#if os(macOS)
extension VaultSelectChainScreen {
    func container<Content: View>(content: () -> Content) -> some View {
        VStack {
            HStack {
                closeButton
                Spacer()
                saveButton
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            content()
        }
        .frame(maxWidth: 700, minHeight: 600)
    }
}
#else
extension VaultSelectChainScreen {
    func container<Content: View>(content: () -> Content) -> some View {
        content()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
    }
}
#endif


#Preview {
    VaultSelectChainScreen(
        vault: .example,
        isPresented: .constant(true)
    )
}


