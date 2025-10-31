//
//  PlatformSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

extension View {
    func crossPlatformSheet<SheetContent: View>(isPresented: Binding<Bool>, @ViewBuilder sheetContent: @escaping () -> SheetContent) -> some View {
        modifier(CrossPlatformSheet(isPresented: isPresented, sheetContent: sheetContent))
    }
    
    func crossPlatformSheet<Item: Identifiable & Equatable, SheetContent: View>(item: Binding<Item?>, @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) -> some View {
        modifier(PlatformSheetWithItem(item: item, sheetContent: sheetContent))
    }
}

private struct CrossPlatformSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    
    var sheetContent: () -> SheetContent
    
    @Environment(\.sheetPresentedCounterManager) var counterManager
    
    @State var counter: Int = 0
    
    init(isPresented: Binding<Bool>, @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self._isPresented = isPresented
        self.sheetContent = sheetContent
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                sheetContent()
                    .environment(\.isSheetPresented, true)
            }
            .onChange(of: isPresented) { _, newValue in
                // Defer state updates to avoid interfering with sheet animation on macOS 15.5
                Task { @MainActor in
                    if newValue {
                        counterManager.increment()
                        counter = counterManager.counter
                    } else {
                        if counter == 1 {
                            counterManager.resetCounter()
                        } else {
                            counterManager.decrement()
                        }
                    }
                }
            }
    }
}

private struct PlatformSheetWithItem<Item: Identifiable & Equatable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    
    var sheetContent: (Item) -> SheetContent
    
    @Environment(\.sheetPresentedCounterManager) var counterManager
    @State private var isPresented: Bool = false
    
    @State var counter: Int = 0
    
    init(item: Binding<Item?>, @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) {
        self._item = item
        self.sheetContent = sheetContent
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $item) { item in
                sheetContent(item)
                    .environment(\.isSheetPresented, true)
            }
            .onChange(of: item) { _, newValue in
                // Defer state updates to avoid interfering with sheet animation on macOS 15.5
                Task { @MainActor in
                    if newValue != nil {
                        counterManager.increment()
                        counter = counterManager.counter
                    } else {
                        if counter == 1 {
                            counterManager.resetCounter()
                        } else {
                            counterManager.decrement()
                        }
                    }
                }
            }
    }
}
