//
//  Loader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-21.
//

import SwiftUI

struct Loader: View {
    var body: some View {
        ZStack {
            overlay
            loader
        }
    }
    
    var overlay: some View {
        Color.black
            .ignoresSafeArea()
            .opacity(0.3)
    }
    
    var loader: some View {
        VStack(spacing: 20) {
            ProgressView()
                .preferredColorScheme(.dark)
            
            Text(NSLocalizedString("pleaseWait", comment: ""))
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
        }
        .frame(width: 180, height: 120)
        .background(Color.blue600)
        .cornerRadius(10)
    }
}

// MARK: - Non-blocking Loaders

struct InlineLoader: View {
    var body: some View {
        ProgressView()
            .scaleEffect(0.6)
            .preferredColorScheme(.dark)
            .frame(width: 24, height: 24)
            .background(Color.blue600.opacity(0.7))
            .cornerRadius(8)
    }
}

struct ButtonLoader: View {
    var body: some View {
        ProgressView()
            .scaleEffect(0.7)
            .preferredColorScheme(.dark)
            .frame(width: 32, height: 32)
            .background(Color.blue600.opacity(0.8))
            .cornerRadius(10)
    }
}

struct SwapLoader: View {
    var body: some View {
        ProgressView()
            .scaleEffect(1.2)
            .preferredColorScheme(.dark)
            .frame(width: 60, height: 60)
            .background(Color.blue600.opacity(0.9))
            .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        Loader()
        InlineLoader()
        ButtonLoader()
        SwapLoader()
    }
}
