//
//  PeerDiscoveryInfoBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-28.
//

import SwiftUI
import RiveRuntime

struct PeerDiscoveryInfoBanner: View {
    @Binding var isPresented: Bool
    
    let animationVM = RiveViewModel(fileName: "PeerDiscoveryInfoBanner", autoPlay: true)
    
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        VStack(spacing: 36) {
            display
            text
            button
        }
    }
    
    var display: some View {
        ZStack {
            image
            animation
        }
        .edgesIgnoringSafeArea(.top)
    }
    
    var image: some View {
        Image("PeerDiscoveryInfoBanner")
            .resizable()
            .frame(width: 290, height: 230)
    }
    
    var animation: some View {
        animationVM.view()
            .frame(width: 80, height: 80)
            .offset(x: -80, y: 6)
    }
    
    var text: some View {
        VStack(spacing: 12) {
            title
            description
        }
    }
    
    var title: some View {
        Group {
            Text(NSLocalizedString("peerDiscoveryInfoTitle1", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("peerDiscoveryInfoTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(.body22BrockmannMedium)
    }
    
    var description: some View {
        Text(NSLocalizedString("peerDiscoveryInfoDescription", comment: ""))
            .multilineTextAlignment(.center)
            .font(.body14BrockmannMedium)
            .foregroundColor(.lightText)
            .padding(.horizontal, 32)
    }
    
    var button: some View {
        Button {
            isPresented = false
        } label: {
            FilledButton(title: "gotIt")
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
}

#Preview {
    PeerDiscoveryInfoBanner(isPresented: .constant(false))
}
