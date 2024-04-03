//
//  Loader.swift
//  VoltixApp
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

#Preview {
    Loader()
}
