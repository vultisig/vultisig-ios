//
//  DefiChainLPPositionSkeletonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/10/2025.
//

import SwiftUI

struct DefiChainLPPositionSkeletonView: View {
    var body: some View {
        ContainerView {
            VStack(spacing: 16) {
                // Header skeleton
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Theme.radius.xs.shape
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 120, height: 16)

                        Theme.radius.xs.shape
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 80, height: 24)
                    }

                    Spacer()
                }

                Separator(color: Theme.colors.borderLight, opacity: 1)

                // APR section skeleton
                HStack(spacing: 4) {
                    Theme.radius.xs.shape
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 60, height: 16)

                    Spacer()

                    Theme.radius.xs.shape
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 50, height: 16)
                }

                // Position amount skeleton
                VStack(alignment: .leading, spacing: 6) {
                    Theme.radius.xs.shape
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 80, height: 16)

                    Theme.radius.xs.shape
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 200, height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Buttons skeleton
                // The real row draws `DefiButton`s, which style themselves with
                // `PrimaryButtonStyle` and are therefore capsules. The
                // placeholder has to be the shape it stands in for, or the
                // buttons visibly change shape the moment the data lands.
                HStack(alignment: .top, spacing: 16) {
                    Theme.radius.pill.shape
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(height: 44)

                    Theme.radius.pill.shape
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(height: 44)
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}
