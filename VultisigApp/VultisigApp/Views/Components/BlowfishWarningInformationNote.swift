import SwiftUI

struct BlowfishWarningInformationNote: View {
    
    @State var blowfishResponse: BlowfishResponse? = nil
    
    var body: some View {
        
        // We must show nothing if nil
        if let response = blowfishResponse {
            if response.warnings.isEmpty {
                
                HStack(spacing: 12) {
                    icon
                    text
                }
                .padding(12)
                .background(Color.green.opacity(0.35))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                    #if os(iOS)
                        .stroke(Color.green, lineWidth: 1)
                    #elseif os(macOS)
                        .stroke(Color.green, lineWidth: 2)
                    #endif
                )
                
            } else {
                HStack(spacing: 12) {
                    icon
                    text
                }
                .padding(12)
                .background(Color.warningYellow.opacity(0.35))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                    #if os(iOS)
                        .stroke(Color.warningYellow, lineWidth: 1)
                    #elseif os(macOS)
                        .stroke(Color.warningYellow, lineWidth: 2)
                    #endif
                )
            }
        }
    }
    
    var icon: some View {
        if let response = blowfishResponse, response.warnings.isEmpty {
            Image(systemName: "checkmark.shield")
                .foregroundColor(Color.green)
        } else {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(Color.warningYellow)
        }
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let response = blowfishResponse, response.warnings.isEmpty {
                Text(NSLocalizedString("scannedByBlowfish", comment: ""))
                    .foregroundColor(.neutral0)
                    .font(.body12MontserratSemiBold)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
            } else {
                if let response = blowfishResponse {
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
}

#Preview {
    ZStack {
        Background()
        BlowfishWarningInformationNote()
    }
}
