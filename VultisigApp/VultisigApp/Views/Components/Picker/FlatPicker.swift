//
//  FlatPicker.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

/// Custom Picker using ScrollView to visualize elements with non-3D effect like the built-in Picker/UIPicker
public struct FlatPicker<ItemView: View, Item: Equatable & Hashable>: View {
    @Binding var selectedItem: Item?
    let items: [Item]
    let itemViewBuilder: (Item) -> ItemView
    let itemSize: CGFloat
    let axis: Axis.Set
    
    var enumerated: [(Int, Item)] {
        Array(items.enumerated())
    }

    public init(selectedItem: Binding<Item?>, items: [Item], itemSize: CGFloat, axis: Axis.Set = .vertical, @ViewBuilder itemViewBuilder: @escaping (Item) -> ItemView) {
        self._selectedItem = selectedItem
        self.items = items
        self.itemSize = itemSize
        self.axis = axis
        self.itemViewBuilder = itemViewBuilder
    }

    @State private var scrollOffset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0.0
    @State private var currentVisibleIndex: Int = 0
    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var scrollCheckWorkItem: DispatchWorkItem?
#if os(iOS)
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
#endif
    
    public var body: some View {
        GeometryReader { geometry in
            let containerSize = axis == .vertical ? geometry.size.height : geometry.size.width
            ZStack {
                ScrollViewReader { proxy in
                    OffsetObservingScrollView(axes: axis, showsIndicators: false, contentInset: containerSize / 2, scrollOffset: $scrollOffset) {
                        itemsContainer {
                            ForEach(enumerated, id: \.0) { (offset, item) in
                                itemViewBuilder(item)
                                    .id(offset)
                            }
                        }
                    }
                    .onChange(of: scrollOffset) { _, newOffset in
                        // Calculate current visible index for haptic feedback
                        let newIndex = calculateIndex(newOffset: newOffset, containerSize: containerSize)
                        
                        // Trigger haptic feedback when passing through a new item
                        if newIndex != currentVisibleIndex {
                            #if os(iOS)
                                impactGenerator.impactOccurred()
                            #endif
                            currentVisibleIndex = newIndex
                        }
                        
                        scrollCheckWorkItem?.cancel()

                        // Updates lastOffset only if the user stops scrolling
                        let workItem = DispatchWorkItem {
                            lastOffset = newOffset
                        }

                        scrollCheckWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
                    }
                    .onChange(of: lastOffset) { _, lastOffset in
                        let newItemIndex = calculateIndex(newOffset: lastOffset, containerSize: containerSize)
                        
                        if selectedItem != items[newItemIndex] {
                            selectedItem = items[newItemIndex]
                        }
                            
                        updateSelectedItem(animated: true)
                    }
                    .onLoad {
                        scrollViewProxy = proxy
                        // Initialize current visible index
                        updateCurrentVisibilityIndex(animated: false)
                    }
                    .onChange(of: selectedItem) { _, _ in
                        updateCurrentVisibilityIndex(animated: true)
                    }
                }
                overlayingGradientsView
            }
        }
    }
}

private extension FlatPicker {
    func calculateIndex(newOffset: CGFloat, containerSize: CGFloat) -> Int {
        let center = (containerSize - itemSize) / 2
        let offset = -newOffset + center
        let index = Int(round(offset / itemSize))
        let clampedIndex = min(max(index, 0), items.count - 1)
        return clampedIndex
    }
    
    func updateCurrentVisibilityIndex(animated: Bool) {
        guard let selectedItem else { return }
        if let initialIndex = items.firstIndex(of: selectedItem) {
            currentVisibleIndex = initialIndex
        }
        // Scroll to selected item on load
        updateSelectedItem(animated: animated)
    }
    
    func updateSelectedItem(animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollViewProxy?.scrollTo(currentVisibleIndex, anchor: .center)
            }
        } else {
            scrollViewProxy?.scrollTo(currentVisibleIndex, anchor: .center)
        }
    }
}

private extension FlatPicker {
    var overlayingGradientsView: some View {
        gradientContainer {
            gradientView(isStart: true)
            Spacer()
            gradientView(isStart: false)
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    func gradientContainer<Gradients: View>(@ViewBuilder content: () -> Gradients) -> some View {
        if axis == .vertical {
            VStack { content() }
        } else {
            HStack { content() }
        }
    }

    @ViewBuilder
    func gradientView(isStart: Bool) -> some View {
        let size = itemSize * 0.2
        LinearGradient(
            gradient: Gradient(colors: [Theme.colors.bgPrimary, Theme.colors.bgPrimary.opacity(0.8), Theme.colors.bgPrimary.opacity(0)]),
            startPoint: gradientStartPoint(isStart: isStart),
            endPoint: gradientEndPoint(isStart: isStart)
        )
        .frame(width: axis == .horizontal ? size : nil, height: axis == .vertical ? size : nil)
    }
    
    func gradientStartPoint(isStart: Bool) -> UnitPoint {
        switch axis {
        case .vertical:
            return isStart ? .top : .bottom
        case .horizontal:
            return isStart ? .leading : .trailing
        default:
            return .top
        }
    }
    
    func gradientEndPoint(isStart: Bool) -> UnitPoint {
        switch axis {
        case .vertical:
            return isStart ? .bottom : .top
        case .horizontal:
            return isStart ? .trailing : .leading
        default:
            return .top
        }
    }
    
    @ViewBuilder
    func itemsContainer<Items: View>(@ViewBuilder content: () -> Items) -> some View {
        switch axis {
        case .vertical:
            LazyVStack(spacing: 0) { content() }
        case .horizontal:
            LazyHStack(spacing: 0) { content() }
        default:
            EmptyView()
        }
    }
}
