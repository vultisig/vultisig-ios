//
//  VultiTabBarControls.swift
//  VultisigApp
//

import SwiftUI

/// The floating tab pill and accessory button the tab pager draws over its pages.
struct VultiTabBarControls<Item: TabBarItem>: View {
    @Binding var selectedItem: Item
    let items: [Item]
    /// Fractional item index, so the indicator can track a page mid-drag.
    let indicatorPosition: CGFloat
    var accessory: Item?
    var onAccessory: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tabWidth: CGFloat = 88
    private let selectionSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// How much wider the pill grows at the midpoint between two tabs.
    private let pillStretch: CGFloat = 0.35
    /// How much flatter it gets there, so the stretch reads as liquid.
    private let pillSquash: CGFloat = 0.12
    private let iconBounceScale: CGFloat = 1.22

    var body: some View {
        ZStack(alignment: .bottom) {
            bottomGradient

            HStack {
                customTabBar
                Spacer()
                if let accessory {
                    TabBarAccessoryButton(icon: accessory.icon) {
                        onAccessory?()
                    }
                    .unwrap(accessory.accessibilityID) { view, id in
                        view.accessibilityIdentifier(id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }
}

private extension VultiTabBarControls {
    var highlightedIndex: Int {
        Int(indicatorPosition.rounded())
    }

    var bottomGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17), location: 0.50),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0.5), location: 0.85),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 1),
            endPoint: UnitPoint(x: 0.5, y: 0)
        )
        .opacity(0.7)
        .frame(height: 80)
    }

    var customTabBar: some View {
        ZStack(alignment: .leading) {
            selectedTabPill

            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button { selectedItem = item } label: {
                        let color = index == highlightedIndex ? Theme.colors.textPrimary : Theme.colors.textTertiary
                        VStack(spacing: 4) {
                            Icon(
                                item.icon,
                                color: color,
                                size: 24
                            )
                            .keyframeAnimator(
                                initialValue: CGFloat(1),
                                trigger: highlightedIndex
                            ) { icon, scale in
                                icon.scaleEffect(index == highlightedIndex && !reduceMotion ? scale : 1)
                            } keyframes: { _ in
                                SpringKeyframe(iconBounceScale, duration: 0.14, spring: .snappy)
                                SpringKeyframe(1, duration: 0.45, spring: .bouncy(extraBounce: 0.25))
                            }
                            Text(item.name)
                                .font(Theme.fonts.caption10)
                                .foregroundStyle(color)
                        }
                        .frame(width: tabWidth)
                        .contentShape(Rectangle())
                        .animation(selectionSpring, value: highlightedIndex)
                    }
                    .buttonStyle(.plain)
                    .unwrap(item.accessibilityID) { view, id in
                        view.accessibilityIdentifier(id)
                    }
                }
            }
        }
        .padding(6)
        .background(tabsBackground)
        .frame(height: 64)
    }

    var selectedTabPill: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                Capsule()
                    .glassEffectTransition(.materialize)
                    .glassEffect(.regular.interactive())

            } else {
                Theme.radius.pill.shape
                    .fill(.white.opacity(0.06))
            }
        }
        .frame(width: tabWidth * (1 + pillStretch * stretch))
        .scaleEffect(y: 1 - pillSquash * stretch)
        // Grows from its centre, so the stretch reaches towards both tabs.
        .offset(x: indicatorPosition * tabWidth - tabWidth * pillStretch * stretch / 2)
        .animation(selectionSpring, value: selectedItem)
    }

    /// `0` when the indicator rests on a tab, `1` halfway between two.
    var stretch: CGFloat {
        guard !reduceMotion else { return 0 }
        let travel = indicatorPosition - indicatorPosition.rounded(.down)
        return sin(.pi * travel)
    }

    var tabsBackground: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular)
            } else {
                Theme.radius.pill.shape
                    .fill(Color(hex: "0C2546"))
                    .overlay(
                        Theme.radius.pill.shape
                            .inset(by: 0.5)
                            .stroke(Color(red: 0.02, green: 0.11, blue: 0.23), lineWidth: 1)
                    )
            }
        }
    }
}
