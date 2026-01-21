//
//  VultiTabBar.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VultiTabBar<Item: TabBarItem, Content: View>: View {
    @Binding var selectedItem: Item
    let items: [Item]
    var content: (Item) -> Content
    var accessory: Item?
    var onAccessory: (() -> Void)?

    private let tabWidth: CGFloat = 88

    init(
        selectedItem: Binding<Item>,
        items: [Item],
        accessory: Item?,
        @ViewBuilder content: @escaping (Item) -> Content,
        onAccessory: (() -> Void)?
    ) {
        self._selectedItem = selectedItem
        self.items = items
        self.content = content
        self.accessory = accessory
        self.onAccessory = onAccessory
    }

    var body: some View {
        Group {
#if os(macOS)
            legacyTabBar
#else
            if #available(iOS 26.0, *), !isIPadOS {
                glassTabBar
            } else {
                legacyTabBar
            }
#endif
        }.onChange(of: selectedItem) { oldValue, newValue in
            if newValue == accessory {
                selectedItem = oldValue
                onAccessory?()
            }
        }
    }
}

// MARK: - iOS 26.0

private extension VultiTabBar {
    @ViewBuilder
    var glassTabBar: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            TabView(selection: $selectedItem) {
                ForEach(items) { item in
                    Tab(value: item) {
                        content(item)
                    } label: {
                        tabBarItem(for: item)
                    }
                }

                if let accessory {
                    Tab(value: accessory, role: .search) {
                        EmptyView()
                    } label: {
                        tabBarItem(for: accessory)
                    }
                }
            }
        }
    }
}

// MARK: - iOS < 26.0

private extension VultiTabBar {
    var selectedTabIndex: Int {
        items.firstIndex(where: { $0.id == selectedItem.id }) ?? 0
    }

    var legacyTabBar: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedItem) {
                ForEach(items) { item in
                    content(item)
                        .tag(item)
                        #if os(iOS)
                        .tabItem { tabBarItem(for: item) }
                        #endif

                }
                #if os(iOS)
                .toolbar(.hidden, for: .tabBar)
                #endif
            }
            .groupedTabViewStyle()

            bottomGradient

            HStack {
                customTabBar
                Spacer()
                if let accessory {
                    TabBarAccessoryButton(icon: accessory.icon) {
                        onAccessory?()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(.all)
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
        .ignoresSafeArea(.all)
    }

    var customTabBar: some View {
        ZStack(alignment: .leading) {
            selectedTabPill

            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { selectedItem = item } label: {
                        let color = item == selectedItem ? Theme.colors.textPrimary : Theme.colors.textTertiary
                        VStack(spacing: 4) {
                            Icon(
                                named: item.icon,
                                color: color,
                                size: 24
                            )
                            Text(item.name)
                                .font(Theme.fonts.caption10)
                                .foregroundStyle(color)
                        }
                        .frame(width: tabWidth)
                        .contentShape(Rectangle())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedItem)
                    }
                    .buttonStyle(.plain)
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
                RoundedRectangle(cornerRadius: 99)
                    .fill(.white.opacity(0.06))
            }
        }
        .frame(width: tabWidth)
        .offset(x: CGFloat(selectedTabIndex) * tabWidth)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedItem)
    }

    var tabsBackground: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular)
            } else {
                RoundedRectangle(cornerRadius: 99)
                    .fill(Color(hex: "0C2546"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 99)
                            .inset(by: 0.5)
                            .stroke(Color(red: 0.02, green: 0.11, blue: 0.23), lineWidth: 1)
                    )
            }
        }
    }

    func tabBarItem(for tab: Item) -> some View {
        Label {
            Text(tab.name)
                .font(Theme.fonts.caption10)
        } icon: {
            Image(tab.icon)
        }
    }

}

#Preview {
    let items = [HomeTab.wallet, .defi]

    VultiTabBar(
        selectedItem: .constant(HomeTab.wallet),
        items: items,
        accessory: .camera
    ) { item in
        switch item {
        case .wallet:
            Color.blue.ignoresSafeArea()
                .overlay(Text("Wallet").foregroundColor(.white))
                .tag(HomeTab.wallet)
        case .defi:
            Color.green.ignoresSafeArea()
                .overlay(Text("Earn").foregroundColor(.white))
                .tag(HomeTab.defi)
        case .camera:
            EmptyView()
        }
    } onAccessory: {}
}
