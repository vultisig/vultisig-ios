//
//  CounterView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct CounterView: View {
    @Binding var count: Int
    let minimumValue: Int

    private var disabled: Bool { count == minimumValue }
    private let cellHeight: CGFloat = 52
    private let iconSize: CGFloat = 20

    init(count: Binding<Int>, minimumValue: Int) {
        self._count = count
        self.minimumValue = minimumValue
    }

    var body: some View {
        HStack(spacing: 8) {
            counterButton(icon: .minus) {
                count -= 1
            }
            .disabled(disabled)
            .opacity(disabled ? 0.2 : 1)

            Text("\(count)")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(count < 1 ? Theme.colors.textTertiary : Theme.colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
                .overlay(
                    Theme.radius.md.shape
                        .strokeBorder(Theme.colors.borderNormal, lineWidth: 1)
                )

            counterButton(icon: .plus) {
                count += 1
            }
        }
    }

    func counterButton(icon: ImageResource, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Icon(icon, color: Theme.colors.textPrimary, size: iconSize)
                .frame(maxWidth: .infinity)
                .frame(height: cellHeight)
                .surface(Theme.colors.bgSurface1, radius: Theme.radius.md)
                .contentShape(Theme.radius.md.shape)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CounterView(count: .constant(5), minimumValue: 1)
}
