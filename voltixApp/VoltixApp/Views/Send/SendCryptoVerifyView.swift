//
//  SendCryptoVerifyView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoVerifyView: View {
    var body: some View {
        ZStack {
            background
            view
        }
        .gesture(DragGesture())
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            
        }
    }
}

#Preview {
    SendCryptoVerifyView()
}
