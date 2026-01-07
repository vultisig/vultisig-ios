//
//  BottomSheetModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

// Copyright DApps Platform Inc. All rights reserved.

import Foundation
import SwiftUI

public extension View {
    func bottomSheet<Content: BottomSheetContentView>(isPresented: Binding<Bool>, dismissable: Bool = true, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(BottomSheetModifier(isPresented: isPresented, dismissable: dismissable, sheetContent: content))
    }
}

public protocol BottomSheetProperties {
    var bgColor: Color? { get }
}

extension BottomSheetProperties {
    var bgColor: Color? { nil }
}
public typealias BottomSheetContentView = View & BottomSheetProperties

struct BottomSheetModifier<SheetContent: BottomSheetContentView>: ViewModifier {
    @Binding private var isPresented: Bool
    @State private var sizedSheetHeight: CGFloat = .zero

    private let sheetContent: SheetContent
    private let dismissable: Bool

    init(
        isPresented: Binding<Bool>,
        dismissable: Bool,
        @ViewBuilder sheetContent: () -> SheetContent
    ) {
        self._isPresented = isPresented
        self.dismissable = dismissable
        self.sheetContent = sheetContent()
    }

    func body(content: Content) -> some View {
        nativeBottomSheet(content: content)
    }
}

// MARK: - >= iOS 16

private extension BottomSheetModifier {
    func nativeBottomSheet(content: Content) -> some View {
        content.crossPlatformSheet(isPresented: $isPresented) {
            VStack {
                BottomSheetContainer {
                    sheetContent
                }
                .overlay {
                    GeometryReader { geometry in
                        Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
                    }
                }
                Spacer()
            }
            .presentationDetents(presentationDetents())
            .presentationBackground(sheetContent.bgColor ?? Theme.colors.bgSurface1)
            .if(!dismissable) {
                $0.interactiveDismissDisabled()
            }
            .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
                if sizedSheetHeight == 0, newHeight > 0 {
                    sizedSheetHeight = newHeight
                }
            }
        }
    }

    func presentationDetents() -> Set<PresentationDetent> {
        guard sizedSheetHeight > 0 else {
            return [.fraction(0.3)]
        }
        let headerHeight: CGFloat = 20
        return [.height(sizedSheetHeight + headerHeight)]
    }
}
