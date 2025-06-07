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
        ZStack {
            shadow
            content
        }
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(.alertTurquoise)
            .opacity(0.05)
            .blur(radius: 20)
            .padding(-15)
    }
    
    var content: some View {
        VStack(spacing: 16) {
            loader
            title
            deviceID
        }
        .multilineTextAlignment(.center)
        .padding(30)
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
        HStack(spacing: 0) {
            Text(NSLocalizedString("thisDevice", comment: ""))
            Text(":")
            Text(viewModel.localPartyID)
                .padding(.leading)
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.extraLightGray)
    }
}

#Preview {
    KeysignStartView(viewModel: JoinKeysignViewModel())
}
