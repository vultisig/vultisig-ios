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
}

struct FilledSegmentedControl<T: FilledSegmentedControlType>: View {
    @Binding var selection: T
    let options: [T]

    var selectionIndex: Int {
        options.firstIndex { $0.id == selection.id } ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                let size = proxy.size.width / CGFloat(options.count)
                RoundedRectangle(cornerRadius: 99)
                    .fill(Theme.colors.bgPrimary)
                    .frame(width: size)
                    .offset(x: CGFloat(selectionIndex) * size)
                    .animation(.interpolatingSpring, value: selectionIndex)

                HStack {
                    ForEach(options) { option in
                        Button {
                            withAnimation {
                                self.selection = option
                            }
                        } label: {
                            Text(option.title)
                                .font(Theme.fonts.bodySMedium)
                                .foregroundStyle(Theme.colors.textPrimary)
                                .padding(16)
                                .frame(maxWidth: .infinity)
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .frame(width: proxy.size.width)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 99)
                    .fill(Theme.colors.bgSurface2)
            )
        }
        .frame(height: 60)
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
