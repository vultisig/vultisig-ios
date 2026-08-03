//
//  AssetSelectionContainerSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

/// Resolution state of a single section's asset list.
///
/// Sections that resolve synchronously stay `.loaded` — the default — so a
/// section with no assets and no pending work is a genuine empty result. A
/// section backed by the network reports `.loading` / `.failed` so the picker
/// can tell "still arriving" and "could not be fetched" apart from "none".
enum AssetSectionState: Hashable {
    case loaded
    case loading
    /// Carries its own user-facing message so the generic picker stays free of
    /// any feature's copy.
    case failed(message: String)

    var isLoading: Bool {
        self == .loading
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct AssetSection<SectionType: Hashable, Asset: Hashable>: Hashable {
    let title: String?
    let type: SectionType
    let assets: [Asset]
    let state: AssetSectionState

    init(title: String? = nil, type: SectionType, assets: [Asset], state: AssetSectionState = .loaded) {
        self.title = title
        self.type = type
        self.assets = assets
        self.state = state
    }

    init(title: String? = nil, assets: [Asset], state: AssetSectionState = .loaded) where SectionType == Int {
        self.title = title
        self.type = .zero
        self.assets = assets
        self.state = state
    }
}

struct AssetSelectionContainerSheet<Asset: Hashable, SectionType: Hashable, CellView: View, EmptyStateView: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let elements: [AssetSection<SectionType, Asset>]
    var onSave: () -> Void
    var cellBuilder: (Asset, SectionType) -> CellView
    var emptyStateBuilder: () -> EmptyStateView
    /// Invoked with the section type whose fetch failed. Sections never reach
    /// `.failed` unless the caller puts them there, so this stays `nil` for
    /// pickers whose catalogs resolve synchronously.
    var onRetrySection: ((SectionType) -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        isPresented: Binding<Bool>,
        searchText: Binding<String>,
        elements: [AssetSection<SectionType, Asset>],
        onSave: @escaping () -> Void,
        cellBuilder: @escaping (Asset, SectionType) -> CellView,
        emptyStateBuilder: @escaping () -> EmptyStateView,
        onRetrySection: ((SectionType) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isPresented = isPresented
        self._searchText = searchText
        self.elements = elements
        self.onSave = onSave
        self.cellBuilder = cellBuilder
        self.emptyStateBuilder = emptyStateBuilder
        self.onRetrySection = onRetrySection
    }

    var body: some View {
        content.sheetContainer()
    }

    var content: some View {
        AssetSelectionContainerView(
            title: title,
            subtitle: subtitle,
            searchText: $searchText,
            insets: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0),
            elements: elements,
            cellBuilder: cellBuilder,
            emptyStateBuilder: emptyStateBuilder,
            onRetrySection: onRetrySection
        )
        .supportsLiquidGlass { view, isSupported in
            view.padding(.bottom, isSupported ? 0 : 16)
        }
        .crossPlatformToolbar(showsBackButton: false) {
            #if os(macOS)
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: .xmark) {
                        isPresented.toggle()
                    }
                    .supportsLiquidGlass { view, isSupported in
                        view.padding(.top, isSupported ? 0 : 16)
                    }
                }
            #endif

            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: .check, type: .confirmation) {
                    onSave()
                }
                .supportsLiquidGlass { view, isSupported in
                    view.padding(.top, isSupported ? 0 : 16)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.colors.bgPrimary)
        .presentationDragIndicator(.visible)
        .background(Theme.colors.bgPrimary)
    }
}

#Preview {
    AssetSelectionContainerSheet(
        title: "Select chains",
        isPresented: .constant(true),
        searchText: .constant(""),
        elements: [AssetSection(title: nil, type: 1, assets: [ Coin.example])],
        onSave: {},
        cellBuilder: { _, _ in ChainSelectionGridCell(assets: [.example], isSelected: true, onSelection: { _ in }) },
        emptyStateBuilder: { EmptyView() }
    )
}
