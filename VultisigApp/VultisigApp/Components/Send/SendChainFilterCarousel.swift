//
//  SendChainFilterCarousel.swift
//  VultisigApp
//

import SwiftUI
import VultisigUIResources

/// Which chains the Send asset list shows.
enum SendChainFilter: Hashable {
    case all
    case chain(Chain)

    func includes(_ chain: Chain) -> Bool {
        switch self {
        case .all: true
        case .chain(let selected): selected == chain
        }
    }
}

/// Left-aligned horizontal row of chain chips, "All chains" first. Laid out
/// edge to edge; at rest the first chip sits at `horizontalInset`.
struct SendChainFilterCarousel: View {
    let chains: [Chain]
    @Binding var selection: SendChainFilter
    let horizontalInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let chipSize: CGFloat = 54
    private let iconSize: CGFloat = 28
    private let itemWidth: CGFloat = 70
    private let itemSpacing: CGFloat = 8
    private let labelSpacing: CGFloat = 6

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: itemSpacing) {
                    ForEach(items, id: \.self) { item in
                        chip(for: item) {
                            select(item, proxy: proxy)
                        }
                        .id(item)
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var items: [SendChainFilter] {
        [.all] + chains.map(SendChainFilter.chain)
    }

    private func chip(for item: SendChainFilter, action: @escaping () -> Void) -> some View {
        let isSelected = selection == item
        return Button(action: action) {
            VStack(spacing: labelSpacing) {
                icon(for: item)
                    .frame(width: chipSize, height: chipSize)
                    .background(Circle().fill(Theme.colors.bgSurface1))
                    .overlay(
                        Circle().strokeBorder(
                            isSelected ? Theme.colors.primaryAccent3 : Theme.colors.borderLight,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                    )

                Text(title(for: item))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(isSelected ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: itemWidth)
            .contentShape(Rectangle())
            .animation(.easeInOut, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func icon(for item: SendChainFilter) -> some View {
        switch item {
        case .all:
            Icon(.coins, color: Theme.colors.textPrimary, size: iconSize)
        case .chain(let chain):
            VultisigImage(chain.logo)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
        }
    }

    private func title(for item: SendChainFilter) -> String {
        switch item {
        case .all: "allChains".localized
        case .chain(let chain): chain.displayName
        }
    }

    private func select(_ item: SendChainFilter, proxy: ScrollViewProxy) {
        selection = item
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            proxy.scrollTo(item, anchor: .center)
        }
    }
}
