//
//  HelpTooltip.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

import SwiftUI

struct HelpTooltip<Content: View>: View {
    @Binding var isPresented: Bool
    var maxWidth: CGFloat?
    var arrowTrailingOffset: CGFloat = 20
    @ViewBuilder var content: () -> Content

    @State private var tooltipWidth: CGFloat = 0

    var body: some View {
        Group {
            if isPresented {
                bubble
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
        .animation(.interpolatingSpring, value: isPresented)
    }

    private var bubble: some View {
        content()
            .foregroundStyle(Theme.colors.textDark)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { tooltipWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in
                            tooltipWidth = newValue
                        }
                }
            )
            .background(Theme.colors.textPrimary)
            .clipShape(TooltipShape(arrowXFraction: arrowXFraction))
            .onTapGesture {
                withAnimation(.interpolatingSpring) {
                    isPresented = false
                }
            }
    }

    private var arrowXFraction: CGFloat {
        guard tooltipWidth > 0 else { return 0.94 }
        return (tooltipWidth - arrowTrailingOffset) / tooltipWidth
    }
}

#Preview {
    ZStack(alignment: .topTrailing) {
        Theme.colors.bgPrimary.ignoresSafeArea()
        HelpTooltip(isPresented: .constant(true), maxWidth: 320) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scanning a QR code")
                    .font(Theme.fonts.bodySMedium)
                Text("Point the camera at a QR code to begin.")
                    .font(Theme.fonts.footnote)
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 60)
    }
}
