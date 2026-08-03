//
//  SwapPercentageButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

import SwiftUI

struct SwapPercentageButtons: View {
    let show100: Bool

    var buttonOptions: [Int] {
        show100 ? [25, 50, 75, 100] : [25, 50, 75]
    }

    @State var selectedPercentage: Int? = nil

    @Binding var showAllPercentageButtons: Bool

    let onTap: (Int) -> Void

    var body: some View {
        container
    }
}

#if os(iOS)
import SwiftUI

extension SwapPercentageButtons {
    var container: some View {
        buttons
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }

    var buttons: some View {
        HStack {
            ForEach(buttonOptions, id: \.self) { option in
                getPercentageButton(for: option)
            }
        }
    }

    func getPercentageButton(for option: Int) -> some View {
        Button(
            action: {
                self.selectedPercentage = option
                onTap(option)
            },
            label: {
                getPercentageCell(for: "\(option)", isSelected: self.selectedPercentage == option && !self.showAllPercentageButtons)
            }
        )
        .disabled(self.selectedPercentage == option && !self.showAllPercentageButtons)
    }

    func getPercentageCell(for text: String, isSelected: Bool) -> some View {
        Text(text + "%")
            .font(Theme.fonts.caption12)
            .foregroundStyle(isSelected ? Color.white : Theme.colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.colors.bgPrimary : Theme.colors.bgSurface1)
            // Not the macOS twin's `pill`, and not an oversight: this cell is
            // taller (10pt of vertical padding against macOS's 8), so its 16
            // stayed just under the clamp and rendered as a real 16 where the
            // macOS cell's 32 rendered as a capsule. The two have always looked
            // different; tokenising each at what it draws keeps that true, and
            // makes the difference a design question instead of two numbers.
            .cornerRadius(Theme.radius.lg)
    }
}
#endif

#if os(macOS)
import SwiftUI

extension SwapPercentageButtons {
    var container: some View {
        VStack(spacing: 8) {
            buttons
            separator
        }
        .frame(maxWidth: .infinity)
    }

    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(Theme.colors.bgSurface2)
    }

    var buttons: some View {
        HStack(spacing: 8) {
            ForEach(buttonOptions, id: \.self) { option in
                getPercentageButton(for: option)
            }
        }
    }

    func getPercentageButton(for option: Int) -> some View {
        Button(
            action: {
                self.selectedPercentage = option
                onTap(option)
            },
            label: {
                getPercentageCell(for: "\(option)", isSelected: self.selectedPercentage == option && !self.showAllPercentageButtons)
            }
        )
        .disabled(self.selectedPercentage == option && !self.showAllPercentageButtons)
    }

    func getPercentageCell(for text: String, isSelected: Bool) -> some View {
        Text(text + "%")
            .font(Theme.fonts.caption12)
            .foregroundStyle(isSelected ? Color.white : Theme.colors.textPrimary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Theme.colors.bgPrimary : Theme.colors.bgSurface1)
            .cornerRadius(Theme.radius.pill)
    }
}
#endif
