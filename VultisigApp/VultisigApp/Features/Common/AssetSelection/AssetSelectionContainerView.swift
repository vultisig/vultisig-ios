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
    var onRetrySection: ((SectionType) -> Void)?
    let insets: EdgeInsets

    @State var searchBarFocused: Bool = false

    init(
        title: String? = nil,
        subtitle: String? = nil,
        searchText: Binding<String>,
        insets: EdgeInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0),
        elements: [AssetSection<SectionType, Asset>],
        cellBuilder: @escaping (Asset, SectionType) -> CellView,
        emptyStateBuilder: @escaping () -> EmptyStateView,
        onRetrySection: ((SectionType) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self._searchText = searchText
        self.elements = elements
        self.cellBuilder = cellBuilder
        self.emptyStateBuilder = emptyStateBuilder
        self.onRetrySection = onRetrySection
        self.insets = insets
    }

    var body: some View {
        content
    }

    /// The empty state means "there is genuinely nothing to pick", so a section
    /// that is still loading — or that failed and can be retried — suppresses it.
    /// Sections whose assets resolve synchronously are always `.loaded`, so a
    /// picker with no pending work still shows the empty state exactly as before.
    var showEmptyState: Bool {
        elements.allSatisfy { $0.state == .loaded && $0.assets.isEmpty }
    }

    var content: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 24) {
                textfield
                if showEmptyState {
                    emptyStateBuilder()
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        grid
                            // The catalog resolves asynchronously, so cells arrive
                            // after first paint (and again on every keystroke while
                            // searching). Animate the diff so tokens fade/settle in
                            // instead of the grid snapping to a new layout.
                            .animation(.easeInOut(duration: 0.2), value: elements)
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
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
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
        // Keyed on the section's own type, NOT the whole value: `AssetSection`
        // hashes its asset array, so `id: \.self` changed the section's identity
        // on every catalog update and keystroke. SwiftUI then tore down and
        // rebuilt the entire section — restarting each cell's remote-logo load
        // (tokens visibly re-entered their loading state while typing) and
        // re-seeding each cell's `@State`. With a stable id only real
        // insertions / removals / moves animate.
        ForEach(elements, id: \.type) { section in
            VStack(alignment: .leading, spacing: 8) {
                // A pending or failed section keeps its header so the user can
                // see *which* group is still resolving rather than watching an
                // unlabelled placeholder.
                if let title = section.title, !section.assets.isEmpty || section.state != .loaded {
                    Text(title)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.footnote)
                }

                switch section.state {
                case .loading:
                    LazyVGrid(columns: Array.init(repeating: gridItem, count: 4), spacing: spacing) {
                        ForEach(0..<4, id: \.self) { _ in
                            AssetSelectionGridCellSkeleton()
                        }
                    }
                case .failed(let message):
                    sectionFailureView(message: message, type: section.type)
                case .loaded:
                    LazyVGrid(columns: Array.init(repeating: gridItem, count: 4), spacing: spacing) {
                        ForEach(section.assets, id: \.self) { element in
                            cellBuilder(element, section.type)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// Inline failure row for one section. Deliberately scoped to the section —
    /// the sections that did resolve stay usable while this one is retried.
    @ViewBuilder
    func sectionFailureView(message: String, type: SectionType) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Icon(.triangleWarning, color: Theme.colors.alertWarning, size: 16)

            Text(message)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.footnote)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onRetrySection {
                PrimaryButton(title: "retry".localized, size: .mini) {
                    onRetrySection(type)
                }
                .fixedSize()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface1))
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
