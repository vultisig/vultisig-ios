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
    @State var isDestinationTagExpanded = false

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        VStack(spacing: 14) {
            // Memo input is gated by `Chain.supportsMemo` so per-chain
            // capability lives in the model, not scattered across UI.
            if viewModel.coin.chain.supportsMemo {
                addMemoField
            }
            if viewModel.coin.chain.supportsDestinationTag {
                addDestinationTagField
            }
            if showsTagAndMemoAdvisory {
                tagAndMemoAdvisory
            }
        }
        .onAppear {
            if !viewModel.memo.isEmpty {
                isMemoExpanded = true
            }
            if !viewModel.rippleTag.destinationTag.isEmpty {
                isDestinationTagExpanded = true
            }
        }
        .onChange(of: viewModel.rippleTag.destinationTag) { _, newValue in
            // Autofill (X-address paste) must surface the tag, not hide it
            // behind a collapsed section.
            if !newValue.isEmpty {
                isDestinationTagExpanded = true
            }
        }
        .onChange(of: viewModel.rippleTag.destinationTagFieldNudge) { _, _ in
            // RequireDest hard-block: surface the (empty, collapsed) field
            // the user now has to fill.
            withAnimation {
                isDestinationTagExpanded = true
            }
        }
    }

    var addMemoTitle: some View {
        HStack {
            getFieldTitle("addMemo")
            Spacer()
            chevronIcon(isExpanded: isMemoExpanded)
        }
        .onTapGesture {
            isMemoExpanded.toggle()
        }
    }

    var addDestinationTagTitle: some View {
        HStack {
            getFieldTitle("addDestinationTag")
            Spacer()
            chevronIcon(isExpanded: isDestinationTagExpanded)
        }
        .onTapGesture {
            isDestinationTagExpanded.toggle()
        }
    }

    func chevronIcon(isExpanded: Bool) -> some View {
        Image(systemName: "chevron.down")
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(.easeInOut, value: isExpanded)
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

    var addDestinationTagField: some View {
        // `@Bindable` on the nested sub-VM: a binding can't chain through the
        // parent's `let rippleTag` (read-only key path), so bind locally.
        @Bindable var rippleTag = viewModel.rippleTag
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isDestinationTagExpanded.toggle()
                }
            } label: {
                addDestinationTagTitle
            }

            VStack(alignment: .leading, spacing: 4) {
                DestinationTagTextField(destinationTag: $rippleTag.destinationTag)
                    .disabled(rippleTag.isDestinationTagLocked)

                if rippleTag.isDestinationTagLocked {
                    getFieldTitle("destinationTagFromXAddress")
                }
            }
            .frame(height: isDestinationTagExpanded ? nil : 0, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A tag+memo combo requires every signing device to be up to date (an old
    /// co-signer reads only the memo slot and drops the tag). Non-blocking
    /// advisory — the send still proceeds. Fires only for the REAL combo the
    /// signer builds: a valid tag AND a genuine TEXT memo. A numeric memo is
    /// either the tag echo or the legacy carrier — `makeTransaction` strips it
    /// to a tag-only send, so it must not trip the advisory.
    private var showsTagAndMemoAdvisory: Bool {
        viewModel.coin.chain.supportsDestinationTag
            && RippleDestinationTag.parseTag(viewModel.rippleTag.destinationTag) != nil
            && !viewModel.memo.isEmpty
            && RippleDestinationTag.parseCanonical(viewModel.memo) == nil
    }

    private var tagAndMemoAdvisory: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(NSLocalizedString("xrpTagAndMemoAdvisory", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var separator: some View {
        LinearSeparator()
    }

    private func getFieldTitle(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
    }
}
