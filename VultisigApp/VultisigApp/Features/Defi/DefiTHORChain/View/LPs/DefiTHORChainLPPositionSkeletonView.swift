//
//  DefiTHORChainLPPositionSkeletonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/10/2025.
//

import SwiftUI

struct DefiTHORChainLPPositionSkeletonView: View {
    var body: some View {
        ContainerView {
            VStack(spacing: 16) {
                // Header skeleton
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 120, height: 16)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 80, height: 24)
                    }

                    Spacer()
                }

                Separator(color: Theme.colors.borderLight, opacity: 1)

                // APR section skeleton
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 60, height: 16)

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 50, height: 16)
                }

                // Position amount skeleton
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 80, height: 16)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 200, height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Buttons skeleton
                HStack(alignment: .top, spacing: 16) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(height: 44)

                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(height: 44)
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}
