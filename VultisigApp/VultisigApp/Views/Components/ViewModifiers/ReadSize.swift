//
//  ReadSize.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/10/2025.
//

import SwiftUI

struct ReadSizeViewModifier: ViewModifier {
    let onSizeChange: (CGSize) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            onSizeChange(proxy.size)
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            onSizeChange(newSize)
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
