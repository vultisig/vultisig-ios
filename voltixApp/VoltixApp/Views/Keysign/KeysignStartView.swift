//
//  KeysignStartView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignStartView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            loader
            deviceID
            
            Text(NSLocalizedString("waitingForKeySignStart", comment: "Waiting for the keysign process to start"))
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(30)
        .background(Color.blue600)
        .cornerRadius(10)
        .task {
            await viewModel.waitForKeysignStart()
        }
    }
    
    var loader: some View {
        ProgressView()
            .preferredColorScheme(.dark)
    }
    
    var deviceID: some View {
        HStack {
            Text("thisDevice")
            Text(viewModel.localPartyID)
        }
    }
}

#Preview {
    KeysignStartView(viewModel: JoinKeysignViewModel())
}
