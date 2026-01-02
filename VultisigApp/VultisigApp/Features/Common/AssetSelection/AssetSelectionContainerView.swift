//
//  AssetSelectionContainerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/12/2025.
//

import SwiftUI

struct AssetSelectionContainerView<Asset: Hashable, SectionType: Hashable, CellView: View, EmptyStateView: View>: View {
    let title: String?
    let subtitle: String?
    @Binding var searchText: String
    let elements: [AssetSection<SectionType, Asset>]
    var cellBuilder: (Asset, SectionType) -> CellView
    var emptyStateBuilder: () -> EmptyStateView
    let insets: EdgeInsets
    
    @State var searchBarFocused: Bool = false
    
    init(
        title: String? = nil,
        subtitle: String? = nil,
        searchText: Binding<String>,
        insets: EdgeInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0),
        elements: [AssetSection<SectionType, Asset>],
        cellBuilder: @escaping (Asset, SectionType) -> CellView,
        emptyStateBuilder: @escaping () -> EmptyStateView
    ) {
        self.title = title
        self.subtitle = subtitle
        self._searchText = searchText
        self.elements = elements
        self.cellBuilder = cellBuilder
        self.emptyStateBuilder = emptyStateBuilder
        self.insets = insets
    }
    
    var body: some View {
        content
    }
    
    var showEmptyState: Bool {
        searchText.isNotEmpty && elements.isEmpty
    }
    
    var content: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 24) {
                textfield
                if showEmptyState {
                    emptyStateBuilder()
                } else {
                    ScrollView(showsIndicators: false) {
                        grid
                    }
                    .safeAreaInset(edge: .bottom, content: { Spacer().frame(height: 64) })
                    .safeAreaInset(edge: .top, content: { Spacer().frame(height: 8) })
                    .frame(minHeight: 300)
                }
            }
            .padding(.top, insets.top)
            .padding(.horizontal, insets.leading)
            
            gradientOverlay
        }
        .ignoresSafeArea(.container, edges: .bottom)
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
            if let title {
                Text(title)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.title2)
                    .multilineTextAlignment(.leading)
            }
            
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(Theme.colors.textTertiary)
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
    var grid: some View {
        let spacing: CGFloat = 16
        let gridItem = GridItem(.flexible(), spacing: spacing)
        ForEach(elements, id: \.self) { section in
            VStack(alignment: .leading, spacing: 8) {
                if let title = section.title, !section.assets.isEmpty {
                    Text(title)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.footnote)
                }
                LazyVGrid(columns: Array.init(repeating: gridItem, count: 4), spacing: spacing) {
                    ForEach(section.assets, id: \.self) { element in
                        cellBuilder(element, section.type)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
}

#Preview {
    AssetSelectionContainerView(
        title: "Select chains",
        searchText: .constant(""),
        elements: [AssetSection(title: nil, type: 1, assets: [ Coin.example])],
        cellBuilder: { _, _ in ChainSelectionGridCell(assets: [.example], isSelected: true, onSelection: { _ in }) },
        emptyStateBuilder: { EmptyView() }
    )
}
