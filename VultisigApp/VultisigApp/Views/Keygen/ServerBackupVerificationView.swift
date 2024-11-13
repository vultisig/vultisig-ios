//
//  ServerBackupVerificationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

import SwiftUI

struct ServerBackupVerificationView: View {
    @State var verificationCode = ""
    
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            textField
            Spacer()
            disclaimer
            button
        }
        .padding(.horizontal, 16)
    }
    
    var title: some View {
        Text(NSLocalizedString("enterBackupVerificationCode", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratMedium)
            .multilineTextAlignment(.leading)
            .padding(.top, 30)
    }
    
    var textField: some View {
        TextField(NSLocalizedString("enterCode", comment: "").capitalized, text: $verificationCode)
            .foregroundColor(.neutral500)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .font(.body12MenloBold)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.blue600)
            .cornerRadius(10)
            .colorScheme(.dark)
    }
    
    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("serverBackupVerificationDisclaimer", comment: ""))
            .padding(.bottom, 18)
    }
    
    var button: some View {
        FilledButton(title: "continue")
    }
}

#Preview {
    ServerBackupVerificationView()
}
