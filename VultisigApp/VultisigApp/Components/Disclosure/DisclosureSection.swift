//
//  DisclosureSection.swift
//  VultisigApp
//

import SwiftUI

/// Tappable title row with a rotating chevron that reveals an inner content
/// block. Used for hiding non-essential transaction details (raw function
/// signature + arguments) so the primary summary stays uncluttered, while
/// keeping the information one tap away for power users.
struct DisclosureSection<Content: View>: View {
    let title: String
    let initiallyExpanded: Bool
    let content: () -> Content

    @State private var isExpanded: Bool

    init(
        title: String,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.initiallyExpanded = initiallyExpanded
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text(title.localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }
}
