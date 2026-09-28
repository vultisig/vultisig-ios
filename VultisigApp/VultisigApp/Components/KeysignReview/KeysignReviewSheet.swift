//
//  KeysignReviewSheet.swift
//  VultisigApp
//

import SwiftUI

enum KeysignReviewSheetLayout {
    /// Leaves room for the grabber above the header.
    static let topInset: CGFloat = 22
    static let horizontalInset: CGFloat = 16
    #if os(macOS)
    static let bottomInset: CGFloat = 32
    static let verdictBottomInset: CGFloat = 16
    #else
    static let bottomInset: CGFloat = 0
    static let verdictBottomInset: CGFloat = 0
    #endif
    static let sectionSpacing: CGFloat = 28
    /// The header's round controls: the scan mark and the close button.
    static let controlSize: CGFloat = 32
    static let macOSWidth: CGFloat = 480
    /// The design's sheet corner, which is off the radius scale.
    static let cornerRadius: CGFloat = 34 // swiftlint:disable:this no_raw_corner_radius
}

/// The shared frame of the keysign review sheet: header, scrolling body and
/// pinned footer, or the scan verdict in place of body and footer.
///
/// The sheet is as tall as its content, up to the screen. The content is
/// measured, since a scroll view has no height of its own to offer.
struct KeysignReviewSheet<Content: View, Footer: View, HeaderAccessory: View>: View {
    let title: String
    let scanRing: KeysignReviewScanRing
    let scanStatus: KeysignReviewScanStatus?
    let onClose: () -> Void
    /// Swaps the sheet into `scanStatus`, once a scan result exists. A no-op
    /// default keeps parity fixtures that never tap the mark unchanged.
    let onTapScanMark: () -> Void
    /// `false` lays the body out in place, for rendering the sheet to an
    /// image: `ImageRenderer` does not draw scroll views.
    let bodyScrolls: Bool
    let content: () -> Content
    let footer: () -> Footer
    let headerAccessory: () -> HeaderAccessory

    @State private var bodyHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var verdictHeight: CGFloat = 0
    /// The last complete measurement, held while a switch to the scan status
    /// (or back) waits for the incoming content to be measured.
    @State private var settledHeight: CGFloat?

    init(
        title: String,
        scanRing: KeysignReviewScanRing,
        scanStatus: KeysignReviewScanStatus? = nil,
        onClose: @escaping () -> Void,
        onTapScanMark: @escaping () -> Void = {},
        bodyScrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory
    ) {
        self.title = title
        self.scanRing = scanRing
        self.scanStatus = scanStatus
        self.onClose = onClose
        self.onTapScanMark = onTapScanMark
        self.bodyScrolls = bodyScrolls
        self.content = content
        self.footer = footer
        self.headerAccessory = headerAccessory
    }

    var body: some View {
        VStack(spacing: KeysignReviewSheetLayout.sectionSpacing) {
            KeysignReviewHeader(
                title: title, scanRing: scanRing, onClose: onClose, onTapScanMark: onTapScanMark, accessory: headerAccessory
            )

            if let scanStatus {
                KeysignReviewScanStatusView(status: scanStatus)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { verdictHeight = $0 }
                    .transition(.opacity)
            } else {
                Group {
                    if bodyScrolls {
                        ScrollView { measuredContent }
                            .scrollIndicators(.hidden)
                            .scrollBounceBehavior(.basedOnSize)
                    } else {
                        measuredContent
                    }
                }
                .transition(.opacity)

                footer()
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
        }
        .padding(.top, KeysignReviewSheetLayout.topInset)
        .padding(.horizontal, KeysignReviewSheetLayout.horizontalInset)
        #if os(macOS)
        .padding(.bottom, scanStatus == nil ? KeysignReviewSheetLayout.bottomInset : KeysignReviewSheetLayout.verdictBottomInset)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.bgSurface1)
        .animation(.easeInOut(duration: 0.2), value: scanStatus == nil)
        .onChange(of: contentHeight) { _, height in
            guard let height else { return }
            settledHeight = height
        }
        .modifier(KeysignReviewSheetSizing(contentHeight: contentHeight ?? settledHeight))
    }

    private var measuredContent: some View {
        content()
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
    }

    /// Everything the sheet needs to show without scrolling, once measured.
    var contentHeight: CGFloat? {
        let chrome = KeysignReviewSheetLayout.topInset + KeysignReviewSheetLayout.controlSize + KeysignReviewSheetLayout.sectionSpacing
        if scanStatus != nil {
            guard verdictHeight > 0 else { return nil }
            return (chrome + verdictHeight + KeysignReviewSheetLayout.verdictBottomInset).rounded(.up)
        }
        guard bodyHeight > 0, footerHeight > 0 else { return nil }
        return (chrome + bodyHeight + KeysignReviewSheetLayout.sectionSpacing + footerHeight + KeysignReviewSheetLayout.bottomInset).rounded(.up)
    }
}

extension KeysignReviewSheet where HeaderAccessory == EmptyView {
    init(
        title: String,
        scanRing: KeysignReviewScanRing,
        scanStatus: KeysignReviewScanStatus? = nil,
        onClose: @escaping () -> Void,
        onTapScanMark: @escaping () -> Void = {},
        bodyScrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.init(
            title: title,
            scanRing: scanRing,
            scanStatus: scanStatus,
            onClose: onClose,
            onTapScanMark: onTapScanMark,
            bodyScrolls: bodyScrolls,
            content: content,
            footer: footer,
            headerAccessory: { EmptyView() }
        )
    }
}

private struct KeysignReviewSheetSizing: ViewModifier {
    let contentHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fittedHeight: CGFloat?

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
            .frame(minHeight: 0, idealHeight: fittedHeight, maxHeight: fittedHeight ?? .infinity)
            .onChange(of: contentHeight, initial: true) { _, height in
                // The first measurement should fit before presentation,
                // not animate down from the full available window height.
                let animation: Animation? = fittedHeight == nil || reduceMotion ? nil : .easeInOut(duration: 0.2)
                withAnimation(animation) { fittedHeight = height }
            }
            .presentationSizingFitted()
        #endif
    }
}

/// One transaction-body renderer for both the initiating and joining signer.
/// Each side supplies facts from its own source; the card/row layout is shared.
enum KeysignReviewSummaryContent {
    case send(SendCryptoVerifySummary)
    case swap(SwapReviewSummary)
    case function(FunctionTransactionReviewSummary)
}

struct KeysignReviewSummaryContentView<Disclosures: View>: View {
    let summary: KeysignReviewSummaryContent
    let disclosures: () -> Disclosures

    init(summary: KeysignReviewSummaryContent, @ViewBuilder disclosures: @escaping () -> Disclosures) {
        self.summary = summary
        self.disclosures = disclosures
    }

    var body: some View {
        Group {
            switch summary {
            case .send(let input):
                SendReviewSummaryView(input: input)
            case .swap(let summary):
                SwapReviewSummaryView(summary: summary)
            case .function(let summary):
                FunctionTransactionReviewSummaryView(summary: summary, disclosures: disclosures)
            }
        }
    }
}

extension KeysignReviewSummaryContentView where Disclosures == EmptyView {
    init(summary: KeysignReviewSummaryContent) {
        self.init(summary: summary, disclosures: { EmptyView() })
    }
}
