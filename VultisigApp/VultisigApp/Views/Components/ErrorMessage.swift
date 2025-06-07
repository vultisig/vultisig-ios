//
//  SwiftUIView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct ErrorMessage: View {
    let text: String
    var width: CGFloat = 200
    
    var body: some View {
        VStack(spacing: 24) {
            logo
            title
        }
    }
    
    var logo: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.body24MontserratBold)
            .foregroundColor(.alertYellow)
    }
    
    var title: some View {
        Text(NSLocalizedString(text, comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.alertYellow)
            .frame(maxWidth: width)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        Background()
        ErrorMessage(text: "signInErrorTryAgain")
    }
}
