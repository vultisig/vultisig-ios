//
//  VaultsView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct VaultsView: View {
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Main")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationMenuButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            list
            Spacer()
            cameraButton
        }
    }
    
    var list: some View {
        ScrollView {
            VStack(spacing: 16) {
                VaultCell()
                VaultCell()
                VaultCell()
                VaultCell()
                VaultCell()
                chooseChainsButton
            }
            .padding(.top, 30)
        }
    }
    
    var chooseChainsButton: some View {
        FilledButton(title: "chooseChains", icon: "plus")
            .padding(16)
    }
    
    var cameraButton: some View {
        ZStack {
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
    }
}

#Preview {
    VaultsView()
}
