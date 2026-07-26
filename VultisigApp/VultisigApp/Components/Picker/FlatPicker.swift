//
//  FlatPicker.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

/// Custom Picker using ScrollView to visualize elements with non-3D effect like the built-in Picker/UIPicker
struct FlatPicker<ItemView: View, Item: Equatable & Hashable>: View {
    @Binding var selectedItem: Item?
    let items: [Item]
    let itemViewBuilder: (Item) -> ItemView
    let itemSize: CGFloat
    let axis: Axis.Set

    var enumerated: [(Int, Item)] {
        Array(items.enumerated())
    }

    init(selectedItem: Binding<Item?>, items: [Item], itemSize: CGFloat, axis: Axis.Set = .vertical, @ViewBuilder itemViewBuilder: @escaping (Item) -> ItemView) {
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
    /// True while a programmatic scroll (external selection change / onLoad) is
    /// animating. The offset churn such a scroll produces must NOT be mistaken
    /// for a user drag: while set, the settle handler skips the `selectedItem`
    /// write-back and the per-frame haptic. User drag-to-select stays intact —
    /// the flag is only set for programmatic scrolls, so a physical drag still
    /// writes back and still buzzes.
    @State private var isProgrammaticScroll: Bool = false
    @State private var programmaticScrollResetWorkItem: DispatchWorkItem?
    /// True for the window between this picker writing `selectedItem` from a
    /// drag settle and the resulting `onChange(of: selectedItem)`. It lets that
    /// re-center distinguish its OWN drag-driven change (which must NOT arm the
    /// programmatic-scroll suppression, or a rapid follow-up drag would be
    /// swallowed) from an EXTERNAL selection change such as a chain-button tap.
    @State private var isSelfSelectionUpdate: Bool = false
#if os(iOS)
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
#endif

    var body: some View {
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

                        // Trigger haptic feedback when passing through a new item.
                        // Suppressed during a programmatic scroll so an external
                        // selection's sweep doesn't machine-gun the haptic.
                        if newIndex != currentVisibleIndex {
                            #if os(iOS)
                            if !isProgrammaticScroll {
                                impactGenerator.impactOccurred()
                            }
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
                        // A programmatic scroll (external selection / onLoad) is
                        // in flight: its offset churn must not be written back as
                        // a selection or it would fight the selection that
                        // started it during rapid switching.
                        if isProgrammaticScroll {
                            // This settle IS the programmatic scroll landing:
                            // consume it (no write-back, no re-snap) and disarm
                            // now that it has settled, so a following user drag is
                            // honored immediately. Disarming on the settle itself
                            // (rather than a fixed timer) closes the gap between
                            // the timer and the debounced settle. User drags never
                            // arm the flag, so drag-to-select falls through below.
                            programmaticScrollResetWorkItem?.cancel()
                            isProgrammaticScroll = false
                            return
                        }

                        let newItemIndex = calculateIndex(newOffset: lastOffset, containerSize: containerSize)

                        if selectedItem != items[newItemIndex] {
                            // Mark our own drag-driven write so the ensuing
                            // onChange(of: selectedItem) re-centers WITHOUT arming
                            // suppression — a rapid follow-up drag must still land.
                            isSelfSelectionUpdate = true
                            selectedItem = items[newItemIndex]
                        }

                        updateSelectedItem(animated: true)
                    }
                    .onLoad {
                        scrollViewProxy = proxy
                        // Initialize current visible index (external-style: arm
                        // suppression so the initial scroll isn't written back).
                        updateCurrentVisibilityIndex(animated: false, suppressFeedback: true)
                    }
                    .onChange(of: selectedItem) { _, _ in
                        // Only an EXTERNAL change (parent set it, e.g. a chain
                        // button tap) arms suppression; a change from this
                        // picker's own drag settle does not.
                        let external = !isSelfSelectionUpdate
                        isSelfSelectionUpdate = false
                        updateCurrentVisibilityIndex(animated: true, suppressFeedback: external)
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

    func updateCurrentVisibilityIndex(animated: Bool, suppressFeedback: Bool) {
        guard let selectedItem else { return }
        if let initialIndex = items.firstIndex(of: selectedItem) {
            currentVisibleIndex = initialIndex
        }
        // Arm suppression only for externally-driven scrolls (chain-button tap /
        // onLoad): their scrollTo animation drives offset churn that must not be
        // written back as a competing selection. A re-center that followed this
        // picker's own drag settle passes `suppressFeedback: false`, so a rapid
        // follow-up user drag is still honored.
        if suppressFeedback {
            beginProgrammaticScroll()
        }
        // Scroll to selected item on load
        updateSelectedItem(animated: animated)
    }

    /// Arms programmatic-scroll suppression. The flag is normally cleared when
    /// the scroll's settle lands (see the `lastOffset` handler); this timer is a
    /// safety net that disarms if no settle ever fires (e.g. a scrollTo that
    /// produces no offset change because the target is already centered). It is
    /// set well past the 0.2s scrollTo animation plus the 0.15s settle debounce
    /// (with margin for janky frames) so a real settle always disarms first and
    /// the timer only fires for the no-offset-change case. Overlapping
    /// programmatic scrolls (rapid external switching) cancel and reschedule it.
    func beginProgrammaticScroll() {
        isProgrammaticScroll = true
        programmaticScrollResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { isProgrammaticScroll = false }
        programmaticScrollResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
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
