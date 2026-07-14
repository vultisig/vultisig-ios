//
//  FilledSegmentedControl.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/12/2025.
//

import SwiftUI

protocol FilledSegmentedControlType: Identifiable {
    var id: Int { get }
    var title: String { get }
    var icon: String? { get }
    var iconSelectedTint: Color? { get }
}

extension FilledSegmentedControlType {
    var icon: String? { nil }
    var iconSelectedTint: Color? { nil }
}

enum FilledSegmentedControlSize {
    case normal
    case small
    /// Resource toggle styling per Figma (track surface1, selected pill surface2,
    /// 52pt tall, 12pt option padding). Distinct case so the macOS scanner keeps
    /// its existing look.
    case filledPill
}

struct FilledSegmentedControl<T: FilledSegmentedControlType>: View {
    @Binding var selection: T
    let options: [T]
    let size: FilledSegmentedControlSize

    init(selection: Binding<T>, options: [T], size: FilledSegmentedControlSize = .normal) {
        self._selection = selection
        self.options = options
        self.size = size
    }

    var selectionIndex: Int {
        options.firstIndex { $0.id == selection.id } ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            // Clamp to zero: during transient/zero-width layout passes (e.g. while a
            // sheet with presentationDetents is presenting) proxy.size.width can be 0,
            // which drives these widths negative and logs "Invalid frame dimension".
            let trackWidth = max(0, proxy.size.width - trackPadding * 2)
            let gapCount = max(options.count - 1, 0)
            let pillWidth = options.isEmpty
                ? 0
                : max(0, (trackWidth - optionGap * CGFloat(gapCount)) / CGFloat(options.count))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: pillCornerRadius)
                    .fill(pillColor)
                    .frame(width: pillWidth)
                    .offset(x: CGFloat(selectionIndex) * (pillWidth + optionGap))
                    .animation(.interpolatingSpring, value: selectionIndex)

                HStack(spacing: optionGap) {
                    ForEach(options) { option in
                        Button {
                            self.selection = option
                        } label: {
                            optionLabel(for: option)
                                .padding(optionPadding)
                                .frame(maxWidth: .infinity)
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: trackWidth)
            .padding(trackPadding)
            .background(
                RoundedRectangle(cornerRadius: trackCornerRadius)
                    .fill(trackColor)
            )
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func optionLabel(for option: T) -> some View {
        let isSelected = option.id == selection.id
        HStack(spacing: 6) {
            if let icon = option.icon {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(iconTint(for: option, isSelected: isSelected))
            }

            Text(option.title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    private func iconTint(for option: T, isSelected: Bool) -> Color {
        guard isSelected, let tint = option.iconSelectedTint else {
            return Theme.colors.textSecondary
        }
        return tint
    }

    var optionPadding: CGFloat {
        switch size {
        case .normal:
            16
        case .small:
            8
        case .filledPill:
            12
        }
    }

    var trackPadding: CGFloat {
        switch size {
        case .normal, .small:
            4
        case .filledPill:
            4
        }
    }

    var optionGap: CGFloat {
        switch size {
        case .normal, .small:
            0
        case .filledPill:
            12
        }
    }

    var trackColor: Color {
        switch size {
        case .normal, .small:
            Theme.colors.bgSurface2
        case .filledPill:
            Theme.colors.bgSurface1
        }
    }

    var pillColor: Color {
        switch size {
        case .normal, .small:
            Theme.colors.bgPrimary
        case .filledPill:
            Theme.colors.bgSurface2
        }
    }

    var trackCornerRadius: CGFloat {
        switch size {
        case .normal, .small:
            99
        case .filledPill:
            88
        }
    }

    var pillCornerRadius: CGFloat {
        switch size {
        case .normal, .small:
            99
        case .filledPill:
            77
        }
    }

    var height: CGFloat? {
        switch size {
        case .normal:
            60
        case .small:
            30
        case .filledPill:
            52
        }
    }
}

#Preview {
    enum FilledTestType: String, FilledSegmentedControlType {
        case option1, option2

        var id: Int {
            hashValue
        }

        var title: String {
            rawValue
        }
    }

    @Previewable @State var selection = FilledTestType.option1
    return FilledSegmentedControl(selection: $selection, options: [.option1, .option2])
}
