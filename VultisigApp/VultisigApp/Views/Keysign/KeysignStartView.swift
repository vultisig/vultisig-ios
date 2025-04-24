//
//  KeysignStartView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI
import RiveRuntime

struct KeysignStartView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    
    @State var loadingAnimationVM: RiveViewModel? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            loader
            title
            deviceID
        }
        .multilineTextAlignment(.center)
        .padding(30)
        .background(Color.blue600)
        .cornerRadius(10)
        .onAppear {
            loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
        }
        .task {
            await viewModel.waitForKeysignStart()
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("waitingForKeySignStart", comment: "Waiting for the keysign process to start"))
            .preferredColorScheme(.dark)
            .font(.body22BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var loader: some View {
        loadingAnimationVM?.view()
            .frame(width: 24, height: 24)
    }
    
    var deviceID: some View {
        HStack {
            Text(NSLocalizedString("thisDevice", comment: ""))
            Text(viewModel.localPartyID)
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.extraLightGray)
    }
}

#Preview {
    KeysignStartView(viewModel: JoinKeysignViewModel())
}
