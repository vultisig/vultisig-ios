//
//  DefiTHORChainBondedSkeletonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/10/2025.
//

import SwiftUI

struct DefiTHORChainBondedSkeletonView: View {
    var body: some View {
        VStack(spacing: 14) {
            // Bonded section skeleton
            bondedSectionSkeleton

            // Active nodes skeleton
            activeNodesSkeleton
        }
    }

    var bondedSectionSkeleton: some View {
        ContainerView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 100, height: 16)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 140, height: 24)
                    }

                    Spacer()
                }

                Separator(color: Theme.colors.border, opacity: 1)

                // Bond button skeleton
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.colors.borderLight.opacity(0.3))
                    .frame(height: 44)
            }
        }
        .redacted(reason: .placeholder)
    }

    var activeNodesSkeleton: some View {
        ContainerView {
            VStack(spacing: 16) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 100, height: 20)

                    Spacer()

                    Circle()
                        .fill(Theme.colors.borderLight.opacity(0.3))
                        .frame(width: 20, height: 20)
                }

                // Node item skeleton
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 12) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.colors.borderLight.opacity(0.3))
                                .frame(width: 80, height: 16)

                            Spacer()

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.colors.borderLight.opacity(0.3))
                                .frame(width: 100, height: 16)
                        }

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
            }
        }
        .redacted(reason: .placeholder)
    }
}
