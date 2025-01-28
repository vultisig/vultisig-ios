//
//  SetupVaultSwithControl.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-27.
//

import SwiftUI

struct SetupVaultSwithControl: View {
    @Binding var selectedTab: SetupVaultState
    
    @State var width: CGFloat = .zero
    
    var body: some View {
        ZStack {
            capsule
            content
        }
        .padding(6)
        .background(Color.blue400)
        .cornerRadius(100)
        .frame(height: 56)
    }
    
    var capsule: some View {
        HStack {
            RoundedRectangle(cornerRadius: 100)
                .foregroundColor(.blue600)
                .frame(width: (width/2))
                .offset(x: selectedTab == .secure ? 0 : (width/2))
            
            Spacer()
        }
    }
    
    var content: some View {
        GeometryReader { size in
            HStack {
                Button {
                    withAnimation {
                        selectedTab = .secure
                        
                    }
                } label: {
                    secureOption
                }
                
                Button {
                    withAnimation {
                        selectedTab = .fast
                    }
                } label: {
                    fastOption
                }
            }
            .onAppear {
                width = size.size.width
            }
        }
    }
    
    var secureOption: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield")
                .font(.body20Menlo)
                .foregroundColor(selectedTab == .secure ? .alertTurquoise : .neutral0)
            
            Text(NSLocalizedString("secure", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .cornerRadius(100)
    }
    
    var fastOption: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt")
                .font(.body20Menlo)
                .foregroundColor(selectedTab == .secure ? .neutral0 : .warningYellow)
                
            Text(NSLocalizedString("fast", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .cornerRadius(100)
    }
}

#Preview {
    SetupVaultSwithControl(selectedTab: .constant(.secure))
}
