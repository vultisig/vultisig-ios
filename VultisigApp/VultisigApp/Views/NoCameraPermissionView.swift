//
//  NoCameraPermissionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//

import SwiftUI

struct NoCameraPermissionView: View {
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        VStack(spacing: 24) {
            Spacer()
            logo
            title
            Spacer()
            button
        }
    }
    
    var logo: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.title80Menlo)
            .symbolRenderingMode(.multicolor)
    }
    
    var title: some View {
        Text(NSLocalizedString("noCameraPermissionError", comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .frame(maxWidth: 300)
            .multilineTextAlignment(.center)
    }
    
    var button: some View {
        FilledButton(title: "openSettings")
            .padding(40)
    }
}

#Preview {
    NoCameraPermissionView()
}
