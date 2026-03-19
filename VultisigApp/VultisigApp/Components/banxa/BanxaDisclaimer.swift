//
//  BanxaDisclaimer.swift
//  VultisigApp
//
//  Created by Johnny Luo on 26/8/2025.
//
import SwiftUI

struct BanxaDisclaimer: View {
    let url: URL

    @State var continueToBanxa: Bool = false
    var body: some View {
        container
    }

    var container: some View {
        ZStack(alignment: .center) {
            Screen {
                content
            }
            .screenTitle("buy".localized)
        }
    }

    @ViewBuilder
    var content: some View {
        if !continueToBanxa {
            VStack(spacing: 8) {
                Image("banxa-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160)

                Text("Buy or transfer with Banxa")
                    .font(.headline)
                    .padding(10)

                Button {
                    continueToBanxa = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Continue to Banxa")
                            .font(.headline)
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
        }
    }
}

#Preview {
    BanxaDisclaimer(url: URL(string: "https://www.banxa.com")!)
}
