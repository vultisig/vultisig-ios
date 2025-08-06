//
//  SendFormExpandableSection.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/07/2025.
//

import SwiftUI

struct SendFormExpandableSection<Header: View, Content: View>: View {
    let isExpanded: Bool
    let header: () -> Header
    let content: () -> Content
    
    @State var opacity: CGFloat = 0
    @State var height: CGFloat? = 0
        
    init(
        isExpanded: Bool,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
        self.header = header
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header()
            content()
                .padding(.top, 16)
                .clipped()
                .opacity(opacity)
                .frame(height: height)
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .padding(1)
        .onChange(of: isExpanded) { _, _ in
            animate()
        }
        .onLoad {
            animate()
        }
    }
    
    private func animate() {
        if isExpanded {
            withAnimation(.easeInOut(duration: 0.3)) {
                height = nil
            }
            
            withAnimation(.easeInOut(duration: 0.2).delay(0.15)) {
                opacity = 1
            }
        } else {
            withAnimation(.easeInOut(duration: 0.1)) {
                opacity = 0
            }
            
            withAnimation {
                height = 0
            }
        }
    }
}
