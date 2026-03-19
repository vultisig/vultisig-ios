//
//  SendDetailsAdditionalSection.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-03.
//

import SwiftUI

struct SendDetailsAdditionalSection: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel

    @State var isMemoExpanded = false

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        VStack(spacing: 14) {
            addMemoField
        }
        .onAppear {
            if !tx.memo.isEmpty {
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

            MemoTextField(memo: $tx.memo)
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

#Preview {
    SendDetailsAdditionalSection(
        tx: SendTransaction(),
        viewModel: SendDetailsViewModel(),
        sendCryptoViewModel: SendCryptoViewModel()
    )
    .environmentObject(AppViewModel())
}
