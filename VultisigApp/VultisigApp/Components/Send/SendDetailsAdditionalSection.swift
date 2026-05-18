//
//  SendDetailsAdditionalSection.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-03.
//

import SwiftUI

struct SendDetailsAdditionalSection: View {
    @Bindable var viewModel: SendDetailsViewModel

    @State var isMemoExpanded = false

    @EnvironmentObject var appViewModel: AppViewModel

    /// Temporary mitigation for #4326 — Cardano memos silently drop on-chain
    /// because WalletCore doesn't expose CIP-20 auxiliary data yet. Hide the
    /// memo input entirely until proper metadata support lands; tracked in
    /// #4377. Re-enable by removing this guard when #4326 closes.
    private var supportsMemo: Bool {
        viewModel.coin.chain != .cardano
    }

    var body: some View {
        VStack(spacing: 14) {
            if supportsMemo {
                addMemoField
            }
        }
        .onAppear {
            if !viewModel.memo.isEmpty {
                isMemoExpanded = true
            }
        }
    }

    var addMemoTitle: some View {
        HStack {
            getFieldTitle("addMemo")
            Spacer()
            chevronIcon
        }
        .onTapGesture {
            isMemoExpanded.toggle()
        }
    }

    var chevronIcon: some View {
        Image(systemName: "chevron.down")
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .rotationEffect(.degrees(isMemoExpanded ? 180 : 0))
            .animation(.easeInOut, value: isMemoExpanded)
    }

    var addMemoField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isMemoExpanded.toggle()
                }
            } label: {
                addMemoTitle
            }

            MemoTextField(memo: $viewModel.memo)
                .frame(height: isMemoExpanded ? nil : 0, alignment: .top)
                .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var separator: some View {
        LinearSeparator()
    }

    private func getFieldTitle(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textTertiary)
    }
}
