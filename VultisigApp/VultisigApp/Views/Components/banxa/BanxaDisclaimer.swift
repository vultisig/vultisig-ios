//
//  BanxaDisclaimer.swift
//  VultisigApp
//
//  Created by Johnny Luo on 26/8/2025.
//
import SwiftUI

struct BanxaDisclaimer: View {
    @Environment(\.dismiss) var dismiss
    @Binding var continueToBanxa: Bool
    var body: some View {
        VStack(spacing: 8) {
            Image("banxa-logo")
                .resizable()
                .scaledToFit()
                .padding(32)
            
            Text("Buy or transfer with Banxa")
                .font(.headline)
                .foregroundStyle(.black)
                .padding(10)
            
            Button {
                dismiss()
                continueToBanxa = true
            } label: {
                HStack(spacing: 8) {
                    Text("Continue to Banxa")
                        .font(.headline)
                        .foregroundStyle(.black)
                    Image(systemName: "arrow.up.forward.square")
                }
                
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.gray, lineWidth: 2)
                )
            }
            Spacer()
            
        }
    }
}

#Preview {
    BanxaDisclaimer(continueToBanxa: .constant(false))
}
