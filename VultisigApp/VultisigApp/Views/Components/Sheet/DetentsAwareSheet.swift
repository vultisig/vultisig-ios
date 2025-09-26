//
//  DetentsAwareSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

private struct DetentsAwareSheetWithItem<Item: Identifiable & Equatable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    var sheetContent: (Item) -> SheetContent
    
    @State var itemInternal: Item? = nil
    
    func body(content: Content) -> some View {
        content
            .if(item != nil) {
                $0.sheet(item: $itemInternal) {
                    sheetContent($0)
                }
            }
            .onChange(of: item) { _, newValue in
                DispatchQueue.main.async {
                    itemInternal = newValue
                }
            }
            .onChange(of: itemInternal) { _, newValue in
                DispatchQueue.main.async {
                    item = newValue
                }
            }
    }
}

private struct DetentsAwareSheetWithBoolean<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var sheetContent: () -> SheetContent
    
    @State var isPresentedInternal: Bool = false
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresentedInternal) {
                sheetContent()
                    .onDisappear {
                        isPresented = false
                    }
            }
            .onChange(of: isPresented) { _, newValue in
                DispatchQueue.main.async {
                    isPresentedInternal = newValue
                }
            }
    }
}

// Created to fix undefined behavior when presentation detents want to be changed programatically on nested sheets
extension View {
    func detentsAwareSheet<Item: Identifiable & Equatable, SheetContent: View>(item: Binding<Item?>, content: @escaping (Item) -> SheetContent) -> some View {
        modifier(DetentsAwareSheetWithItem(item: item, sheetContent: content))
    }
    
    func detentsAwareSheet<SheetContent: View>(isPresented: Binding<Bool>, content: @escaping () -> SheetContent) -> some View {
        modifier(DetentsAwareSheetWithBoolean(isPresented: isPresented, sheetContent: content))
    }
}


