//
//  HomeSwipeHintView.swift
//  VultisigApp
//

import SwiftUI

/// Bounds of the view the swipe hint points at: the wallet page's section
/// header, just above the content that slides.
struct HomeSwipeHintAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// One-time hint that the home's tabs can be swiped; a swipe on the dimmed layer performs it.
struct HomeSwipeHintView: View {
    let anchor: Anchor<CGRect>
    let onDismiss: () -> Void
    /// `true` for a swipe towards the leading edge, i.e. on to the next tab.
    let onSwipe: (_ towardsNextTab: Bool) -> Void

    private let bubbleWidth: CGFloat = 260
    private let bubbleLeading: CGFloat = 28
    private let arrowGap: CGFloat = 4
    private let dimOpacity: CGFloat = 0.5
    private let swipeMinimumDistance: CGFloat = 30

    var body: some View {
        ZStack {
            Color.black.opacity(dimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .gesture(swipe)

            GeometryReader { proxy in
                let target = proxy[anchor]
                ZStack(alignment: .topLeading) {
                    Color.clear
                    bubble
                        .alignmentGuide(.top) { $0[.bottom] - target.minY + arrowGap }
                        .alignmentGuide(.leading) { _ in -bubbleLeading }
                }
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: swipeMinimumDistance).onEnded { value in
            let translation = value.translation
            guard abs(translation.width) > abs(translation.height) else { return }
            onSwipe(translation.width < 0)
        }
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.left.and.right")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.primaryAccent4)
                .frame(width: 36, height: 36)
                .background(Theme.radius.sm.shape.fill(Theme.colors.primaryAccent4.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("homeSwipeHintTitle".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textDark)
                Text("homeSwipeHintDescription".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onDismiss) {
                    Text("gotIt".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.primaryAccent4)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
                .accessibilityIdentifier(AccessibilityID.Home.swipeHintDismissButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(Theme.colors.textPrimary)
        .clipShape(TooltipShape(arrowXFraction: 0.5, arrowDirection: .down))
    }
}
