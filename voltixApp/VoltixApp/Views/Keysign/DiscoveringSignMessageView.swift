//
//  DiscoveringSignMessageView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct DiscoveringSignMessageView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            title
            button
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("scanQRCodeJoinKeygen", comment: "Scan the barcode on another VoltixApp device to start"))
            .font(.body15MenloBold)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
    }
    
    var button: some View {
        Button(action: {
            viewModel.startScan()
        }) {
            scanButton
        }
    }
    
    var scanButton: some View {
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
    DiscoveringSignMessageView(viewModel: JoinKeysignViewModel())
}
