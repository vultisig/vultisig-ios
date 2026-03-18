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

    @State private var segmentFrames: [Int: CGRect] = [:]

    private var selectedIndex: Int {
        items.firstIndex { $0.value == selection } ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        if item.isEnabled {
                            withAnimation(.interpolatingSpring(duration: 0.3)) {
                                selection = item.value
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(Theme.fonts.bodySMedium)
                                .foregroundStyle(item.isEnabled ? Theme.colors.textPrimary : Theme.colors.textButtonDisabled)

                            if let tag = item.tag {
                                Text(tag)
                                    .font(Theme.fonts.caption10)
                                    .foregroundStyle(Theme.colors.alertInfo)
                                    .padding(6)
                                    .background(Theme.colors.alertInfo.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .disabled(!item.isEnabled)
                    .buttonStyle(.plain)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: SegmentFramePreferenceKey.self,
                                    value: [index: geometry.frame(in: .named("SegmentedControlContainer"))]
                                )
                        }
                    )
                }
            }

            underline
        }
        .coordinateSpace(name: "SegmentedControlContainer")
        .onPreferenceChange(SegmentFramePreferenceKey.self) { frames in
            segmentFrames = frames
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var underline: some View {
        let frame = segmentFrames[selectedIndex]
        let width = frame?.width ?? 0
        let offsetX = frame?.minX ?? 0

        return Rectangle()
            .fill(Theme.colors.primaryAccent4)
            .frame(width: width, height: 2)
            .offset(x: offsetX)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: selection)
    }
}

private struct SegmentFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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
