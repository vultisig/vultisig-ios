//
//  FormSectionHeader.swift
//  VultisigApp
//
//  Shared title-row for the form section components — the title text on
//  the left, optional value preview + a trailing indicator on the right.
//  `FormExpandableSection` uses the `.editable` indicator (check + pencil
//  when collapsed-and-valid, nothing while expanded). `FormPickerSection`
//  uses `.picker` (chevron-right) — it never expands inline, tapping the
//  row drives an external picker / sheet instead.
//

import SwiftUI

struct FormSectionHeader<ValueView: View>: View {
    enum TrailingIndicator {
        case editable
        case picker
        case hidden
    }

    let title: String
    let showValue: Bool
    let indicator: TrailingIndicator
    let action: () -> Void
    @ViewBuilder let valueView: () -> ValueView

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(maxWidth: hasTrailing ? nil : .infinity, alignment: .leading)

                switch indicator {
                case .editable:
                    HStack(spacing: 12) {
                        valueView()
                            .showIf(showValue)
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Theme.colors.alertSuccess)
                            Image(systemName: "pencil")
                                .foregroundStyle(Theme.colors.textPrimary)
                        }
                    }
                case .picker:
                    HStack(spacing: 12) {
                        valueView()
                            .showIf(showValue)
                        Spacer()
                        Icon(.chevronRight, color: Theme.colors.textTertiary, size: 16)
                    }
                case .hidden:
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hasTrailing: Bool {
        switch indicator {
        case .editable, .picker:
            return showValue
        case .hidden:
            return false
        }
    }
}
