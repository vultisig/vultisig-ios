//
//  KeysignDiscoverServiceView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignDiscoverServiceView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    @ObservedObject var serviceDelegate: ServiceDelegate
    
    var body: some View {
        VStack(spacing: 16) {
            loader
            deviceID
            
            Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(30)
        .background(Color.blue600)
        .cornerRadius(10)
        .onAppear {
            viewModel.discoverService()
        }
    }
    
    var loader: some View {
        ZStack {
            if self.serviceDelegate.serverURL == nil {
                ProgressView()
                    .preferredColorScheme(.dark)
            } else {
                Image(systemName: "checkmark")
                    .onAppear {
                        viewModel.serverAddress = self.serviceDelegate.serverURL
                        viewModel.setStatus(status: .JoinKeysign)
                    }
            }
        }
        .padding(.bottom, 18)
    }
    
    var deviceID: some View {
        HStack {
            Text(NSLocalizedString("thisDevice", comment: ""))
            Text(viewModel.localPartyID)
        }
    }
}

#Preview {
    KeysignDiscoverServiceView(viewModel: JoinKeysignViewModel(), serviceDelegate: ServiceDelegate())
}
