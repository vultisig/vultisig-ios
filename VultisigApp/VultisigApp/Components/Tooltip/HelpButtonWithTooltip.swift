//
//  HelpButtonWithTooltip.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

import SwiftUI

struct HelpButtonWithTooltip<TooltipContent: View>: View {
    @Binding var isPresented: Bool
    var buttonSize: CGFloat = 44
    var iconSize: CGFloat = 22
    var tooltipGap: CGFloat = 8
    var tooltipMaxWidth: CGFloat?
    @ViewBuilder var tooltipContent: () -> TooltipContent

    @State private var tooltipWidth: CGFloat = 0

    var body: some View {
        Button {
            withAnimation(.interpolatingSpring) { isPresented.toggle() }
        } label: {
            Icon(named: "circle-info", color: Theme.colors.textPrimary, size: iconSize)
                .frame(width: buttonSize, height: buttonSize)
                .background(glassCircleBackground)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isPresented {
                tooltipView
                    .offset(y: buttonSize + tooltipGap)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
        .animation(.interpolatingSpring, value: isPresented)
    }

    private var tooltipView: some View {
        tooltipContent()
            .foregroundStyle(Theme.colors.textDark)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: tooltipMaxWidth, alignment: .leading)
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
        let offsetFromTrailing = buttonSize / 2
        return (tooltipWidth - offsetFromTrailing) / tooltipWidth
    }

    private var glassCircleBackground: some View {
        Circle()
            .fill(Color.white.opacity(0.05))
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.05),
                                Color.clear,
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .glassy(shape: Circle())
    }
}

#Preview {
    ZStack(alignment: .topTrailing) {
        Theme.colors.bgPrimary.ignoresSafeArea()

        HelpButtonWithTooltip(
            isPresented: .constant(true),
            tooltipMaxWidth: 320
        ) {
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
