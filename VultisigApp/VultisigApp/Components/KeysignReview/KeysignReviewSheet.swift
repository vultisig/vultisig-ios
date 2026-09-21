//
//  KeysignReviewSheet.swift
//  VultisigApp
//

import SwiftUI

enum KeysignReviewSheetLayout {
    /// Leaves room for the grabber above the header.
    static let topInset: CGFloat = 22
    static let horizontalInset: CGFloat = 16
    static let bottomInset: CGFloat = 32
    static let verdictBottomInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let macOSWidth: CGFloat = 480
    /// The design's sheet corner, which is off the radius scale.
    static let cornerRadius: CGFloat = 34 // swiftlint:disable:this no_raw_corner_radius
}

/// The shared frame of the keysign review sheet: header, scrolling body and
/// pinned footer, or the scan verdict in place of body and footer.
///
/// The sheet is as tall as its content, up to the screen. The content is
/// measured, since a scroll view has no height of its own to offer.
struct KeysignReviewSheet<Content: View, Footer: View>: View {
    let title: String
    let scanRing: KeysignReviewScanRing
    let verdict: KeysignReviewVerdict?
    let onClose: () -> Void
    let content: () -> Content
    let footer: () -> Footer

    @State private var bodyHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var verdictHeight: CGFloat = 0
    /// The last complete measurement, held while a switch to the verdict (or
    /// back) waits for the incoming content to be measured.
    @State private var settledHeight: CGFloat?

    init(
        title: String,
        scanRing: KeysignReviewScanRing,
        verdict: KeysignReviewVerdict? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.scanRing = scanRing
        self.verdict = verdict
        self.onClose = onClose
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: KeysignReviewSheetLayout.sectionSpacing) {
            KeysignReviewHeader(title: title, scanRing: scanRing, onClose: onClose)

            if let verdict {
                KeysignReviewVerdictView(verdict: verdict)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { verdictHeight = $0 }
                    .transition(.opacity)
            } else {
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity)

                footer()
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
        }
        .padding(.top, KeysignReviewSheetLayout.topInset)
        .padding(.horizontal, KeysignReviewSheetLayout.horizontalInset)
        .padding(.bottom, verdict == nil ? KeysignReviewSheetLayout.bottomInset : KeysignReviewSheetLayout.verdictBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.bgSurface1)
        .animation(.easeInOut(duration: 0.2), value: verdict == nil)
        .onChange(of: contentHeight) { _, height in
            guard let height else { return }
            settledHeight = height
        }
        .modifier(KeysignReviewSheetSizing(contentHeight: contentHeight ?? settledHeight))
    }

    /// Everything the sheet needs to show without scrolling, once measured.
    var contentHeight: CGFloat? {
        let chrome = KeysignReviewSheetLayout.topInset + KeysignReviewHeader.controlSize + KeysignReviewSheetLayout.sectionSpacing
        if verdict != nil {
            guard verdictHeight > 0 else { return nil }
            return (chrome + verdictHeight + KeysignReviewSheetLayout.verdictBottomInset).rounded(.up)
        }
        guard bodyHeight > 0, footerHeight > 0 else { return nil }
        return (chrome + bodyHeight + KeysignReviewSheetLayout.sectionSpacing + footerHeight + KeysignReviewSheetLayout.bottomInset).rounded(.up)
    }
}

private struct KeysignReviewSheetSizing: ViewModifier {
    let contentHeight: CGFloat?

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.colors.bgSurface1)
            .presentationCornerRadius(KeysignReviewSheetLayout.cornerRadius)
            // Snaps to the first measurement, which lands before the sheet is
            // up; later changes (a fee arriving, the verdict) animate.
            .animatedPresentationDetents(
                target: contentHeight.map { .height($0) } ?? .large,
                animatesFirstChange: false
            )
        #else
        content
            .frame(width: KeysignReviewSheetLayout.macOSWidth)
            .frame(minHeight: 0, idealHeight: contentHeight, maxHeight: contentHeight ?? .infinity)
            .presentationSizingFitted()
        #endif
    }
}
