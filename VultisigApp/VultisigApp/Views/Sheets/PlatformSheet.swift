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
        ZStack(alignment: .center) {
            content
                .overlay(isPresented ? overlay : nil)
            
            Screen(showNavigationBar: false) {
                sheetContent()
            }
            .frame(maxWidth: 700, maxHeight: 450)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .showIf(isPresented)
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
                Screen(showNavigationBar: false) {
                    sheetContent()
                }
                .sheetStyle()
            }
    }
#endif
}
