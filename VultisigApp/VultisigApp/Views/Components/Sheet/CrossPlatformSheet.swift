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
    @State private var internalIsPresented: Bool = false

    init(isPresented: Binding<Bool>, @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self._isPresented = isPresented
        self.sheetContent = sheetContent
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            nativeSheet(content: content)
        } else {
            customSheet(content: content)
        }
        #else
        nativeSheet(content: content)
        #endif
    }

    #if os(macOS)
    func customSheet(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: internalIsPresented ? 5 : 0)

            if isPresented {
                // Semi-transparent backdrop
                Color.black.opacity(0.1)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.interpolatingSpring(duration: 0.2)) {
                            internalIsPresented = false
                        }
                    }

                sheetContent()
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .inset(by: 0.5)
                            .strokeBorder(Theme.colors.borderExtraLight)
                    )
            }
        }
        .onChange(of: isPresented) { _, newValue in
            withAnimation(.interpolatingSpring(duration: 0.2)) {
                internalIsPresented = newValue
            }
        }
        .onChange(of: internalIsPresented) { _, newValue in
            guard !newValue else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPresented = false
            }
        }
    }
    #endif

    func nativeSheet(content: Content) -> some View {
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
    @State private var internalItem: Item?

    init(item: Binding<Item?>, @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) {
        self._item = item
        self.sheetContent = sheetContent
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            nativeSheet(content: content)
        } else {
            customSheet(content: content)
        }
        #else
        nativeSheet(content: content)
        #endif
    }

    #if os(macOS)
    func customSheet(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: internalItem != nil ? 5 : 0)

            if let currentItem = internalItem {
                // Semi-transparent backdrop
                Color.black.opacity(0.1)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.interpolatingSpring(duration: 0.2)) {
                            internalItem = nil
                        }
                    }

                sheetContent(currentItem)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .inset(by: 0.5)
                            .strokeBorder(Theme.colors.borderExtraLight)
                    )
            }
        }
        .onChange(of: item) { _, newValue in
            withAnimation(.interpolatingSpring(duration: 0.2)) {
                internalItem = newValue
            }
        }
        .onChange(of: internalItem) { _, newValue in
            guard newValue == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                item = nil
            }
        }
    }
    #endif

    func nativeSheet(content: Content) -> some View {
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
