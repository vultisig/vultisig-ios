//
//  AssetSelectionContainerScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct AssetSelectionContainerScreen<Asset: Hashable, CellView: View, EmptyStateView: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let elements: [Asset]
    var onSave: () -> Void
    var cellBuilder: (Asset) -> CellView
    var emptyStateBuilder: () -> EmptyStateView
    
    @State var searchBarFocused: Bool = false
    
    init(
        title: String,
        subtitle: String? = nil,
        isPresented: Binding<Bool>,
        searchText: Binding<String>,
        elements: [Asset],
        onSave: @escaping () -> Void,
        cellBuilder: @escaping (Asset) -> CellView,
        emptyStateBuilder: @escaping () -> EmptyStateView
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isPresented = isPresented
        self._searchText = searchText
        self.elements = elements
        self.onSave = onSave
        self.cellBuilder = cellBuilder
        self.emptyStateBuilder = emptyStateBuilder
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 24) {
                    textfield
                    Group {
                        if searchText.isNotEmpty && elements.isEmpty {
                            emptyStateBuilder()
                        } else {
                            ScrollView(showsIndicators: false) {
                                chainsGrid
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut, value: searchText)
                }
                .padding(.top, 24)
                .padding(.horizontal, 16)
                
                gradientOverlay
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .crossPlatformToolbar(showsBackButton: false) {
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: "x") {
                        isPresented.toggle()
                    }
                }
                
                CustomToolbarItem(placement: .trailing) {
                    ToolbarButton(image: "check", type: .confirmation) {
                        onSave()
                    }
                }
            }
            .presentationDetents([.large])
            .presentationBackground(Theme.colors.bgPrimary)
            .presentationDragIndicator(.visible)
            
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
            Text(title)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title2)
                .multilineTextAlignment(.leading)
            
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodySMedium)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 12) {
                SearchTextField(value: $searchText, isFocused: $searchBarFocused)
                Button {
                    searchText = ""
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
            ForEach(elements, id: \.self) { element in
                cellBuilder(element)
            }
        }
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    AssetSelectionContainerScreen(
        title: "Select chains",
        isPresented: .constant(true),
        searchText: .constant(""),
        elements: [Coin.example],
        onSave: {},
        cellBuilder: { _ in ChainSelectionGridCell(assets: [.example], onSelection: { _ in }) },
        emptyStateBuilder: { EmptyView() }
    )
}


