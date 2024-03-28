//
//  SwiftUIView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI

struct ErrorMessage: View {
    let text: String
    
    var body: some View {
        VStack(spacing: 24) {
            logo
            title
        }
    }
    
    var logo: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.title80Menlo)
            .symbolRenderingMode(.multicolor)
    }
    
    var title: some View {
        Text(NSLocalizedString(text, comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .frame(maxWidth: 200)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        Background()
        ErrorMessage(text: "signInErrorTryAgain")
    }
}
