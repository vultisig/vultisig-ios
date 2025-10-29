//
//  AssetSelectionContainerScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct AssetSection<SectionType: Hashable, Asset: Hashable>: Hashable {
    let title: String?
    let type: SectionType
    let assets: [Asset]
    
    init(title: String? = nil, type: SectionType, assets: [Asset]) {
        self.title = title
        self.type = type
        self.assets = assets
    }
    
    init(title: String? = nil, assets: [Asset]) where SectionType == Int {
        self.title = title
        self.type = .zero
        self.assets = assets
    }
}

struct AssetSelectionContainerScreen<Asset: Hashable, SectionType: Hashable, CellView: View, EmptyStateView: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let elements: [AssetSection<SectionType, Asset>]
    var onSave: () -> Void
    var cellBuilder: (Asset, SectionType) -> CellView
    var emptyStateBuilder: () -> EmptyStateView
    
    @State var searchBarFocused: Bool = false
    
    init(
        title: String,
        subtitle: String? = nil,
        isPresented: Binding<Bool>,
        searchText: Binding<String>,
        elements: [AssetSection<SectionType, Asset>],
        onSave: @escaping () -> Void,
        cellBuilder: @escaping (Asset, SectionType) -> CellView,
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
        container
    }
    
    var container: some View {
#if os(iOS)
        NavigationStack {
            content
        }
#else
        content
            .presentationSizingFitted()
            .applySheetSize()
            .transaction { $0.disablesAnimations = true }
#endif
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
        .background(Theme.colors.bgPrimary)
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
    var grid: some View {
        let spacing: CGFloat = 16
        let gridItem = GridItem(.flexible(), spacing: spacing)
        ForEach(elements, id: \.self) { section in
            VStack(alignment: .leading, spacing: 8) {
                if let title = section.title {
                    Text(title)
                        .foregroundStyle(Theme.colors.textExtraLight)
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
    AssetSelectionContainerScreen(
        title: "Select chains",
        isPresented: .constant(true),
        searchText: .constant(""),
        elements: [AssetSection(title: nil, type: 1, assets: [ Coin.example])],
        onSave: {},
        cellBuilder: { _, _ in ChainSelectionGridCell(assets: [.example], isSelected: true, onSelection: { _ in }) },
        emptyStateBuilder: { EmptyView() }
    )
}


