import SwiftUI

struct BlowfishWarningInformationNote: View {
    
    @State var blowfishMessages: [BlowfishResponse.BlowfishWarning] = []
    
    var body: some View {
        
        if blowfishMessages.isEmpty {
            
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
    
    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundColor(Color.warningYellow)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            if blowfishMessages.isEmpty {
                Text("Transaction Scanned Successfully! You are cleared to proceed with safety.") // Assuming `message` has a `message` property
                    .foregroundColor(.neutral0)
                    .font(.body12MontserratSemiBold)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(blowfishMessages) { blowfishMessage in
                    Text(blowfishMessage.message) // Assuming `message` has a `message` property
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
