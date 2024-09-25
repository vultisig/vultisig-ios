//
//  KeysignDiscoveryView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension KeysignDiscoveryView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var container: some View {
        content
            .detectOrientation($orientation)
    }
    
    var view: some View {
        VStack {
            switch viewModel.status {
            case .WaitingForDevices:
                waitingForDevices
            case .WaitingForFast:
                LookingForDevicesLoader()
            case .FailToStart:
                errorText
            }
        }
        .blur(radius: isLoading ? 1 : 0)
    }
    
    var orientedContent: some View {
        ZStack {
            if orientation == .landscapeLeft || orientation == .landscapeRight {
                landscapeContent
            } else {
                portraitContent
            }
        }
    }
    
    var list: some View {
        VStack(spacing: 18) {
            networkPrompts
            
            if participantDiscovery.peersFound.count == 0 {
                lookingForDevices
                    .frame(height: idiom == .phone ? 50 : 150)
            } else {
                deviceList
            }
            
            instructions
        }
    }
    
    var paringQRCode: some View {
        VStack {
            Text(NSLocalizedString("scanWithPairedDevice", comment: ""))
                .font(.body14MontserratMedium)
                .multilineTextAlignment(.center)
            
            qrCodeImage?
                .resizable()
                .frame(maxWidth: isPhoneSE ? 250 : nil)
                .frame(maxHeight: isPhoneSE ? 250 : nil)
                .scaledToFit()
                .padding(2)
                .background(Color.neutral0)
                .cornerRadius(10)
                .padding(4)
                .padding(12)
                .background(Color.blue600)
                .cornerRadius(20)
                .overlay (
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [52]))
                )
                .padding(1)
        }
        .foregroundColor(.neutral0)
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding(20)
    }
    
    var bottomButtons: some View {
        let isDisabled = viewModel.selections.count < (vault.getThreshold() + 1)
        
        return Button {
            isLoading = true
            startKeysign()
        } label: {
            FilledButton(title: "sign")
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.8 : 1)
        .grayscale(isDisabled ? 1 : 0)
        .padding(.horizontal, 40)
        .background(Color.backgroundBlue.opacity(0.95))
        .edgesIgnoringSafeArea(.bottom)
    }
}
#endif
