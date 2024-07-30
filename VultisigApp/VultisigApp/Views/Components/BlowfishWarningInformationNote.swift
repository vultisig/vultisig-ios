//
//  BlowfishWarningInformationNote.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import SwiftUI

struct BlowfishWarningInformationNote: View {
    
    @State var blowfishResponse: BlowfishEvmResponse? = nil
    
    var body: some View {
        guard let response = blowfishResponse else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            HStack(spacing: 12) {
                icon(response: response)
                text(response: response)
            }
                .padding(12)
                .background(response.warnings.isEmpty ? Color.green.opacity(0.35) : Color.warningYellow.opacity(0.35))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(response.warnings.isEmpty ? Color.green : Color.warningYellow, lineWidth: lineWidth)
                )
        )
    }
    
    var lineWidth: CGFloat {
#if os(iOS)
        return 1
#elseif os(macOS)
        return 2
#endif
    }
    
    func icon(response: BlowfishEvmResponse) -> some View {
        Image(systemName: response.warnings.isEmpty ? "checkmark.shield" : "exclamationmark.triangle")
            .foregroundColor(response.warnings.isEmpty ? Color.green : Color.warningYellow)
    }
    
    func text(response: BlowfishEvmResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if response.warnings.isEmpty {
                Text(NSLocalizedString("scannedByBlowfish", comment: ""))
                    .foregroundColor(.neutral0)
                    .font(.body12MontserratSemiBold)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(response.warnings) { blowfishMessage in
                    Text(blowfishMessage.message)
                        .foregroundColor(.neutral0)
                        .font(.body12MontserratSemiBold)
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        BlowfishWarningInformationNote()
    }
}
