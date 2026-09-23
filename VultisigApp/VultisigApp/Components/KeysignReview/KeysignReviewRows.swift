//
//  KeysignReviewRows.swift
//  VultisigApp
//

import SwiftUI
import VultisigUIResources

/// A label on the left and its value on the right.
struct KeysignReviewRow<Value: View>: View {
    let label: String
    let value: () -> Value

    init(label: String, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .keysignReviewText(.footnote)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 0)

            value()
        }
        .frame(maxWidth: .infinity)
    }
}

extension KeysignReviewRow where Value == KeysignReviewRowValue {
    /// A text value, with a 16pt image before it when `image` names one.
    /// Single values truncate in the middle, so an address keeps both ends.
    init(
        label: String,
        value: String,
        image: String? = nil,
        color: Color = Theme.colors.textPrimary,
        isMultiline: Bool = false
    ) {
        self.init(label: label) {
            KeysignReviewRowValue(text: value, image: image, color: color, isMultiline: isMultiline)
        }
    }
}

struct KeysignReviewRowValue: View {
    let text: String
    let image: String?
    let color: Color
    let isMultiline: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let image {
                VultisigImage(image)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(text)
                .keysignReviewText(.bodyS)
                .foregroundStyle(color)
                .lineLimit(isMultiline ? nil : 1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A fee: the token amount over its fiat value.
struct KeysignReviewFeeRow: View {
    let label: String
    let amount: String
    let fiat: String

    var body: some View {
        KeysignReviewRow(label: label) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(amount)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(fiat)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .keysignReviewText(.bodyS)
            .lineLimit(1)
        }
    }
}

/// A compact row, as used by the swap's provider, slippage and fee lines.
struct KeysignReviewDetailRow<Value: View>: View {
    let label: String
    let value: () -> Value

    init(label: String, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .keysignReviewText(.caption)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 0)

            value()
        }
        .frame(maxWidth: .infinity)
    }
}

extension KeysignReviewDetailRow where Value == KeysignReviewDetailValue {
    init(label: String, value: String, color: Color = Theme.colors.textPrimary) {
        self.init(label: label) {
            KeysignReviewDetailValue(text: value, color: color)
        }
    }
}

struct KeysignReviewDetailValue: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .keysignReviewText(.caption)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

struct KeysignReviewHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.colors.borderLight)
            .frame(height: 1)
    }
}

/// Which vault is signing: its name, then a shortened address.
struct KeysignReviewVaultLine: View {
    let name: String
    let address: String

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("(\(address.truncatedAddress))")
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .keysignReviewText(.bodyS)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        // The design gives this line a 17pt box and lets the text overhang it.
        .frame(height: 17)
    }
}

/// A total that unfolds into the rows it adds up.
struct KeysignReviewDisclosure<Rows: View>: View {
    let title: String
    let value: String
    let rows: () -> Rows

    @State private var isExpanded: Bool

    init(title: String, value: String, isInitiallyExpanded: Bool = false, @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.value = value
        self.rows = rows
        _isExpanded = State(initialValue: isInitiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                // Let the sheet measure the final layout in one pass. Animating
                // this stack's height produces a stream of intermediate detents,
                // which makes the native sheet chase the content in a second,
                // delayed animation.
                isExpanded.toggle()
            } label: {
                KeysignReviewRow(label: title) {
                    HStack(spacing: 4) {
                        Text(value)
                            .keysignReviewText(.bodyS)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .lineLimit(1)
                        KeysignReviewChevron()
                            .stroke(Theme.colors.textPrimary, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                            .frame(width: 12, height: 12)
                            .rotationEffect(.degrees(isExpanded ? -90 : 90))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(spacing: 11) {
                    Rectangle()
                        .fill(Theme.colors.primaryAccent4)
                        .frame(width: 1)
                    VStack(spacing: 12) {
                        rows()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// The design's small chevron, pointing right in a 12pt box.
struct KeysignReviewChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 12
        var path = Path()
        path.move(to: CGPoint(x: 4.5 * scale, y: 2 * scale))
        path.addLine(to: CGPoint(x: 8.5 * scale, y: 6 * scale))
        path.addLine(to: CGPoint(x: 4.5 * scale, y: 10 * scale))
        return path
    }
}
