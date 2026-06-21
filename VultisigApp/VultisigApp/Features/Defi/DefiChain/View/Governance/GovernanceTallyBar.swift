//
//  GovernanceTallyBar.swift
//  VultisigApp
//
//  Horizontal stacked bar showing the Yes / No / NoWithVeto / Abstain split
//  of a proposal tally, plus an optional per-option legend with percentages.
//  Percentages are computed client-side from the raw counts.
//

import SwiftUI

struct GovernanceTallyBar: View {
    let tally: CosmosGovTallyResult
    /// When true, renders the four-option legend with percentages beneath the
    /// bar. The compact list row omits it; the detail shows it.
    var showsLegend: Bool = false

    /// Options in display order with their counts.
    private var segments: [(choice: CosmosGovVoteChoice, count: Decimal)] {
        [
            (.yes, tally.yes),
            (.no, tally.no),
            (.noWithVeto, tally.noWithVeto),
            (.abstain, tally.abstain)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bar
            if showsLegend {
                legend
            }
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if tally.total > 0 {
                    ForEach(segments, id: \.choice) { segment in
                        Rectangle()
                            .fill(segment.choice.tallyColor)
                            .frame(width: width(for: segment.count, total: geometry.size.width))
                    }
                } else {
                    Rectangle()
                        .fill(Theme.colors.bgSurface2)
                        .frame(width: geometry.size.width)
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    private var legend: some View {
        VStack(spacing: 6) {
            ForEach(segments, id: \.choice) { segment in
                HStack(spacing: 8) {
                    Circle()
                        .fill(segment.choice.tallyColor)
                        .frame(width: 8, height: 8)
                    Text(segment.choice.displayTitle)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                    Spacer()
                    Text(percentString(for: segment.count))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
        }
    }

    private func width(for count: Decimal, total: CGFloat) -> CGFloat {
        let fraction = tally.fraction(of: count)
        return total * CGFloat(truncating: NSDecimalNumber(decimal: fraction))
    }

    private func percentString(for count: Decimal) -> String {
        let fraction = tally.fraction(of: count)
        let percent = NSDecimalNumber(decimal: fraction * 100)
        return String(format: "%.1f%%", percent.doubleValue)
    }
}
