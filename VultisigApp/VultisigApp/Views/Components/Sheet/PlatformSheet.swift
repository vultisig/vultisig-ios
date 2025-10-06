//
//  PlatformSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

extension View {
    func platformSheet<SheetContent: View>(isPresented: Binding<Bool>, @ViewBuilder sheetContent: @escaping () -> SheetContent) -> some View {
        modifier(PlatformSheet(isPresented: isPresented, sheetContent: sheetContent))
    }
}

struct PlatformSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    
    var sheetContent: () -> SheetContent
    
    init(isPresented: Binding<Bool>, @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self._isPresented = isPresented
        self.sheetContent = sheetContent
    }
    
    func body(content: Content) -> some View {
        #if os(macOS)
            macOS(content: content)
        #else
            iOS(content: content)
        #endif
    }
    
#if os(macOS)
    func macOS(content: Content) -> some View {
        content
            .overlay(isPresented ? sheetView : nil)
    }
    
    var sheetView: some View {
        ZStack {
            overlay
            sheetContent()
        }
    }
    
    var overlay: some View {
        MacOSOverlay()
            .onTapGesture { isPresented.toggle() }
    }
#else
    func iOS(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                sheetContent()
            }
    }
#endif
}

struct FullScreenSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        Screen(showNavigationBar: false) {
            content()
        }
        .frame(maxWidth: 700, maxHeight: 450)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        #else
        Screen(showNavigationBar: false) {
            content
        }
        .sheetStyle()
        #endif
    }
}

extension View {
    func fullScreenSheet() -> some View {
        modifier(FullScreenSheetModifier())
    }
}
