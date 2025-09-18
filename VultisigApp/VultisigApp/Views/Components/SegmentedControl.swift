//
//  SegmentedControl.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct SegmentedControlItem<T: Hashable> {
    let value: T
    let title: String
    let tag: String?
    let isEnabled: Bool
    
    init(value: T, title: String, tag: String? = nil, isEnabled: Bool = true) {
        self.value = value
        self.title = title
        self.tag = tag
        self.isEnabled = isEnabled
    }
}

struct SegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let items: [SegmentedControlItem<T>]
    
    @State private var segmentFrames: [CGRect] = []
    
    private var selectedIndex: Int {
        items.firstIndex { $0.value == selection } ?? 0
    }
    
    init(selection: Binding<T>, items: [SegmentedControlItem<T>]) {
        self._selection = selection
        self.items = items
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button(action: {
                        if item.isEnabled {
                            withAnimation(.interpolatingSpring(duration: 0.3)) {
                                selection = item.value
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(Theme.fonts.bodySMedium)
                                .foregroundStyle(item.isEnabled ? Theme.colors.textPrimary : Theme.colors.textButtonDisabled)
                                
                            if let tag = item.tag {
                                Text(tag)
                                    .font(Theme.fonts.caption10)
                                    .foregroundColor(Theme.colors.alertInfo)
                                    .padding(6)
                                    .background(Theme.colors.alertInfo.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(item.value == selection ? .white : (item.isEnabled ? Color.gray : Color.gray.opacity(0.5)))
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        updateFrame(for: index, frame: geometry.frame(in: .named("SegmentedControlContainer")))
                                    }
                                    .onChange(of: geometry.frame(in: .named("SegmentedControlContainer"))) { _, newFrame in
                                        updateFrame(for: index, frame: newFrame)
                                    }
                            }
                        )
                    }
                    .disabled(!item.isEnabled)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.colors.primaryAccent4)
                    .frame(width: segmentFrames[safe: selectedIndex]?.width ?? 0, height: 2)
                    .offset(x: segmentFrames[safe: selectedIndex]?.minX ?? 0)
                    .animation(.easeInOut(duration: 0.3), value: selection)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(name: "SegmentedControlContainer")
        .scaledToFit()
    }
    
    private func updateFrame(for index: Int, frame: CGRect) {
        if segmentFrames.count <= index {
            segmentFrames = Array(repeating: .zero, count: items.count)
        }
        segmentFrames[index] = frame
    }
    
}

extension SegmentedControl {
    init(selection: Binding<T>, items: [(value: T, title: String)]) {
        self._selection = selection
        self.items = items.map { SegmentedControlItem(value: $0.value, title: $0.title) }
    }
    
    init(selection: Binding<T>, items: [(value: T, title: String, isEnabled: Bool)]) {
        self._selection = selection
        self.items = items.map { SegmentedControlItem(value: $0.value, title: $0.title, isEnabled: $0.isEnabled) }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State private var selectedTab = "Portfolio"
        @State private var selectedOption = 0
        
        var body: some View {
            VStack(spacing: 30) {
                SegmentedControl(
                    selection: $selectedTab,
                    items: [
                        SegmentedControlItem(value: "Portfolio", title: "Portfolio"),
                        SegmentedControlItem(value: "NFTs", title: "NFTs", isEnabled: false),
                        SegmentedControlItem(value: "Soon", title: "Soon", tag: "NEW")
                    ]
                )
                .padding()
                
                SegmentedControl(
                    selection: $selectedOption,
                    items: [
                        SegmentedControlItem(value: 0, title: "Option 1"),
                        SegmentedControlItem(value: 1, title: "Option 2", isEnabled: false),
                        SegmentedControlItem(value: 2, title: "NFTs")
                    ]
                )
                .padding()
                
                Spacer()
            }
            .background(Color.black)
        }
    }
    
    return PreviewContainer()
}
