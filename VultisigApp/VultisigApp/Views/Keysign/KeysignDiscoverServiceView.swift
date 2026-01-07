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
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.textPrimary)
        .multilineTextAlignment(.center)
        .padding(30)
        .background(Theme.colors.bgSurface1)
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
                    }.task {
                        await viewModel.ensureKeysignPayload()
                        viewModel.setStatus(status: .JoinKeysign)
                    }
            }
        }
        .padding(.bottom, 18)
    }
    
    var deviceID: some View {
        HStack {
            Text(NSLocalizedString("thisDevice", comment: ""))
            Text(":")
            Text(viewModel.localPartyID)
        }
    }
}

#Preview {
    KeysignDiscoverServiceView(viewModel: JoinKeysignViewModel(), serviceDelegate: ServiceDelegate())
}
