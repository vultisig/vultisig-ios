//
//  DefiTHORChainStakedPositionSkeletonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/10/2025.
//

import SwiftUI

struct DefiTHORChainStakedPositionSkeletonView: View {
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
                            .frame(width: 100, height: 16)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 140, height: 24)
                    }

                    Spacer()
                }

                Separator(color: Theme.colors.borderLight, opacity: 1)

                // Rewards section skeleton
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 50, height: 16)

                        Spacer()

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 60, height: 16)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 90, height: 16)

                        Spacer()

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.borderLight.opacity(0.3))
                            .frame(width: 80, height: 16)
                    }
                }

                Separator(color: Theme.colors.border, opacity: 1)

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
