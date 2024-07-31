//
//  BlowfishWarningInformationNote.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import SwiftUI

struct BlowfishSolanaWarningInformationNote: View {
    
    @State var blowfishResponse: BlowfishResponse? = nil
    
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
                .background((response.aggregated?.warnings?.isEmpty ?? true) ? Color.green.opacity(0.35) : Color.warningYellow.opacity(0.35))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke((response.aggregated?.warnings?.isEmpty ?? true) ? Color.green : Color.warningYellow, lineWidth: lineWidth)
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
    
    func icon(response: BlowfishResponse) -> some View {
        Image(systemName: (response.aggregated?.warnings?.isEmpty ?? true) ? "checkmark.shield" : "exclamationmark.triangle")
            .foregroundColor((response.aggregated?.warnings?.isEmpty ?? true) ? Color.green : Color.warningYellow)
    }
    
    func text(response: BlowfishResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if response.aggregated?.warnings?.isEmpty ?? true {
                Text(NSLocalizedString("scannedByBlowfish", comment: ""))
                    .foregroundColor(.neutral0)
                    .font(.body12MontserratSemiBold)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(response.aggregated?.warnings ?? []) { blowfishMessage in
                    Text(blowfishMessage.message ?? "")
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
        BlowfishSolanaWarningInformationNote()
    }
}
