//
//  KeysignDiscovery.swift
//  VultisigApp

import OSLog
import SwiftUI

struct KeysignDiscoveryView: View {
    let vault: Vault
    let keysignPayload: KeysignPayload
    let transferViewModel: TransferViewModel
    @Binding var keysignView: KeysignView?
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    
    @StateObject var participantDiscovery = ParticipantDiscovery(isKeygen: false)
    @StateObject var viewModel = KeysignDiscoveryViewModel()
    
    @State var isLoading = false
    @State var qrCodeImage: Image? = nil
    @State var selectedNetwork = NetworkPromptType.Internet
#if os(iOS)
    @State private var orientation = UIDevice.current.orientation
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
#endif
    
    @Environment(\.displayScale) var displayScale
    
    let columns = [
        GridItem(.adaptive(minimum: 160)),
        GridItem(.adaptive(minimum: 160)),
    ]
    
    let logger = Logger(subsystem: "keysign-discovery", category: "view")
    
    var body: some View {
        ZStack {
            Background()
            view
            
            if isLoading {
                loader
            }
        }
        .onAppear {
            setData()
        }
        .task {
            await viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
#if os(iOS)
        .detectOrientation($orientation)
#endif
    }
    
    var view: some View {
        VStack {
            switch viewModel.status {
            case .WaitingForDevices:
                waitingForDevices
            case .FailToStart:
                errorText
            }
        }
        .blur(radius: isLoading ? 1 : 0)
    }
    
    var loader: some View {
        Loader()
    }
    
    var errorText: some View {
        SendCryptoStartErrorView(errorText: viewModel.errorMessage)
    }
    
    var waitingForDevices: some View {
        ZStack {
            if participantDiscovery.peersFound.count == 0 {
                VStack(spacing: 16) {
                    content
                    bottomButtons
                }
            } else {
                ZStack(alignment: .bottom) {
                    content
                    bottomButtons
                }
            }
        }
    }
    
    var content: some View {
#if os(iOS)
        ZStack {
            if orientation == .landscapeLeft || orientation == .landscapeRight {
                landscapeContent
            } else {
                portraitContent
            }
        }
#elseif os(macOS)
        landscapeContent
#endif
    }
    
    var landscapeContent: some View {
        HStack {
            paringQRCode
                .padding(60)
            list
                .padding(20)
        }
    }
    
    var portraitContent: some View {
        ZStack {
            if participantDiscovery.peersFound.count == 0 {
                VStack {
                    paringQRCode
                    list
                }
            } else {
                ScrollView {
                    paringQRCode
                    list
                }
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
                .scaledToFit()
                .padding(3)
                .background(Color.neutral0)
                .cornerRadius(10)
                .frame(maxWidth: 512)
                .padding(24)
                .background(Color.blue600)
                .cornerRadius(20)
                .overlay (
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [12]))
                )
                .padding(1)
        }
        .foregroundColor(.neutral0)
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding(.horizontal, 22)
    }
    
    var lookingForDevices: some View {
        LookingForDevicesLoader()
            .padding()
    }
    
    var deviceList: some View {
        LazyVGrid(columns: columns, spacing: 32) {
            ForEach(participantDiscovery.peersFound, id: \.self) { peer in
                Button {
                    handleSelection(peer)
                } label: {
                    PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
                }
                .onAppear {
                    if participantDiscovery.peersFound.count == 1 && participantDiscovery.peersFound.first == peer {
                        handleSelection(peer)
                        startKeysign()
                    }
                }
            }
        }
        .padding(20)
    }
    
    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $selectedNetwork)
    }
    
    var instructions: some View {
        InstructionPrompt(networkType: selectedNetwork)
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
    
    private func setData() {
        if VultisigRelay.IsRelayEnabled {
            self.selectedNetwork = .Internet
        }
        viewModel.setData(vault: vault, keysignPayload: keysignPayload, participantDiscovery: participantDiscovery)
        
        qrCodeImage = viewModel.getQrImage(size: 100)
        
        guard let qrCodeImage else {
            return
        }
        
        shareSheetViewModel.render(
            title: "send",
            qrCodeImage: qrCodeImage,
            displayScale: displayScale
        )
    }
    
    func startKeysign(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let isDisabled = viewModel.selections.count < (vault.getThreshold() + 1)
            if !isDisabled {
                keysignView = viewModel.startKeysign(vault: vault, viewModel: transferViewModel)
            }
        }
    }
    
    
    func handleSelection(_ peer: String) {
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if viewModel.selections.contains(peer) {
                // Don't remove itself
                if peer != viewModel.localPartyID {
                    viewModel.selections.remove(peer)
                }
                isLoading = false
            } else {
                viewModel.selections.insert(peer)
                isLoading = false
            }
        }
    }
}

#Preview {
    KeysignDiscoveryView(vault: Vault.example, keysignPayload: KeysignPayload.example, transferViewModel: SendCryptoViewModel(), keysignView: .constant(nil), shareSheetViewModel: ShareSheetViewModel())
}
