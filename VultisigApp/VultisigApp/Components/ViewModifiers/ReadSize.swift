//
//  ReadSize.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/10/2025.
//

import SwiftUI

struct ReadSizeViewModifier: ViewModifier {
    let onSizeChange: (CGSize) -> Void
    @State private var previousSize: CGSize = .zero
    @State private var debounceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            let currentSize = proxy.size
                            if currentSize != previousSize {
                                previousSize = currentSize
                                onSizeChange(currentSize)
                            }
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            // Cancel any pending debounced call
                            debounceTask?.cancel()

                            // Only update if size actually changed
                            guard newSize != previousSize else { return }

                            // Debounce the size change to avoid multiple calls per frame
                            debounceTask = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(16)) // ~1 frame at 60fps

                                if !Task.isCancelled && newSize != previousSize {
                                    previousSize = newSize
                                    onSizeChange(newSize)
                                }
                            }
                        }
                }
            )
    }
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        modifier(ReadSizeViewModifier(onSizeChange: onChange))
    }
}
