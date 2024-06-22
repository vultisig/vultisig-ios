//
//  Logo.swift
//  VultisigApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct VultisigLogo: View {
    var isAnimated: Bool = true
    
    @State var didAppear = false
    
    var body: some View {
        VStack(spacing: 0) {
            logo
            title
            description
        }
#if os(macOS)
        .scaleEffect(0.9)
        .offset(y: 12)
#endif
        .onAppear {
            setData()
        }
    }
    
    var logo: some View {
        ZStack {
            stroke3
            stroke2
            stroke1
            primaryLogo
        }
    }
    
    var primaryLogo: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 160, height: 160)
            .scaleEffect(didAppear ? 1 : 0)
            .opacity(didAppear ? 1 : 0)
    }
    
    var stroke1: some View {
        Image("VultisigLogoStroke1")
            .resizable()
            .frame(width: 179.8, height: 154.5)
            .offset(y: 2)
            .scaleEffect(didAppear ? 1 : 0)
            .opacity(didAppear ? 1 : 0)
            .animation(
                isAnimated ? .spring(duration: 0.5).delay(0.2) : .none,
                value: didAppear
            )
    }
    
    var stroke2: some View {
        Image("VultisigLogoStroke2")
            .resizable()
            .frame(width: 201.3, height: 171.2)
            .offset(y: 4)
            .scaleEffect(didAppear ? 1 : 0)
            .opacity(didAppear ? 1 : 0)
            .animation(
                isAnimated ? .spring(duration: 0.5).delay(0.3) : .none,
                value: didAppear
            )
    }
    
    var stroke3: some View {
        Image("VultisigLogoStroke3")
            .resizable()
            .frame(width: 222.8, height: 190)
            .offset(y: 5)
            .scaleEffect(didAppear ? 1 : 0)
            .opacity(didAppear ? 1 : 0)
            .animation(
                isAnimated ? .spring(duration: 0.5).delay(0.4) : .none,
                value: didAppear
            )
    }
    
    var title: some View {
        Text("Vultisig")
            .font(.title40MontserratBold)
            .foregroundColor(.neutral0)
            .opacity(didAppear ? 1 : 0)
            .animation(
                isAnimated ? .easeIn(duration: 1) : .none,
                value: didAppear)
    }
    
    var description: some View {
        Text("secureCryptoVault")
            .foregroundColor(.neutral0)
            .opacity(didAppear ? 1 : 0)
            .font(.body16MontserratBold)
#if os(iOS)
            .padding(.top, 10)
#elseif os(macOS)
            .padding(.top, 5)
#endif
    }
    
    private func setData() {
        withAnimation(isAnimated ? .spring : .none) {
            didAppear = true
        }
    }
}

#Preview {
    ZStack {
        Background()
        VultisigLogo()
    }
}
