//
//  BanxaDisclaimer.swift
//  VultisigApp
//
//  Created by Johnny Luo on 26/8/2025.
//
import SwiftUI

struct BanxaDisclaimer: View {
    let url: URL
    @Environment(\.dismiss) var dismiss
    @State var continueToBanxa: Bool = false
    var body: some View {
        if !continueToBanxa {
            VStack(spacing: 8) {
                Image("banxa-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160)
                
                Text("Buy or transfer with Banxa")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(10)
                
                Button {
                    continueToBanxa = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Continue to Banxa")
                            .font(.headline)
                            .foregroundStyle(.black)
                        Image(systemName: "arrow.up.forward.square")
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(Color.gray, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        } else {
            PlatformWebView(url: url)
            #if os(macOS)
                .frame(minWidth: 600, minHeight: 800)
            #endif
        }
    }
}

#Preview {
    BanxaDisclaimer(url: URL(string: "https://www.banxa.com")!)
}
