//
//  SwapQuoteCountdownBadge.swift
//  VultisigApp
//
//  Compact quote-refresh countdown ("0:36" + depleting ring) rendered in the
//  Market/Limit tab row. Market mode only — it feeds `SwapDetailsViewModel.timer`.
//  Limit orders execute at a fixed target price, so there is no live quote to
//  count down to. No pill background — matches Figma 78798:74534.
//

import SwiftUI

struct SwapQuoteCountdownBadge: View {
    /// Seconds remaining in the current refresh window (0…60).
    let seconds: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .monospacedDigit()

            ZStack {
                Circle()
                    .stroke(Theme.colors.borderLight, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(
                        Theme.colors.primaryAccent3,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
        .animation(.easeInOut, value: seconds)
    }

    private var label: String {
        let value = max(0, seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private var progress: Double {
        Double(max(0, min(seconds, 60))) / 60
    }
}

#Preview {
    SwapQuoteCountdownBadge(seconds: 36)
}
