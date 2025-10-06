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
    
    func platformSheet<Item: Identifiable & Equatable, SheetContent: View>(item: Binding<Item?>, @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) -> some View {
        modifier(PlatformSheetWithItem(item: item, sheetContent: sheetContent))
    }
}

struct PlatformSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    
    var sheetContent: () -> SheetContent
    
    @Environment(\.sheetPresentedCounterManager) var counterManager
    
    init(isPresented: Binding<Bool>, @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self._isPresented = isPresented
        self.sheetContent = sheetContent
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                sheetContent()
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    counterManager.increment()
                } else {
                    counterManager.decrement()
                }
            }
    }
}

struct PlatformSheetWithItem<Item: Identifiable & Equatable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    
    var sheetContent: (Item) -> SheetContent
    
    @Environment(\.sheetPresentedCounterManager) var counterManager
    @State private var isPresented: Bool = false
    
    init(item: Binding<Item?>, @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) {
        self._item = item
        self.sheetContent = sheetContent
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $item) { item in
                sheetContent(item)
            }
            .onChange(of: item) { _, newValue in
                if newValue != nil {
                    counterManager.increment()
                } else {
                    counterManager.decrement()
                }
            }
    }
}

struct FullScreenSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        Screen(showNavigationBar: false) {
            content
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


// Observable object to manage sheet counter state
class SheetPresentedCounterManager: ObservableObject {
    @Published var counter: Int = 0
    
    func increment() {
        self.counter += 1
    }
    
    func decrement() {
        guard counter > 0 else { return }
        self.counter -= 1
    }
}

// Environment key for the manager
struct SheetPresentedCounterManagerKey: EnvironmentKey {
    static let defaultValue: SheetPresentedCounterManager = SheetPresentedCounterManager()
}

extension EnvironmentValues {
    var sheetPresentedCounterManager: SheetPresentedCounterManager {
        get { self[SheetPresentedCounterManagerKey.self] }
        set { self[SheetPresentedCounterManagerKey.self] = newValue }
    }
}

struct SheetPresentedViewModifier: ViewModifier {
    @Environment(\.sheetPresentedCounterManager) var sheetPresentedCounterManager
    
    @State var blurContent: Bool = false
    
    func body(content: Content) -> some View {
        content
            .overlay(blurContent ? overlayView : nil)
            .blur(radius: blurContent ? 6 : 0)
            .animation(.interpolatingSpring(duration: 0.15), value: blurContent)
            .onReceive(sheetPresentedCounterManager.$counter) { newValue in
                blurContent = newValue > 0
            }
    }
    
    var overlayView: some View {
        Color.black
            .opacity(0.4)
            .ignoresSafeArea()
    }
}

extension View {
    func sheetPresentedStyle() -> some View {
        modifier(SheetPresentedViewModifier())
    }
}
