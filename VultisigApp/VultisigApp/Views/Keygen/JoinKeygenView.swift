//
//  JoinKeygen.swift
//  VultisigApp

import Network
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct JoinKeygenView: View {
    let vault: Vault
    
    @Query var vaults: [Vault]
    
    @StateObject var viewModel = JoinKeygenViewModel()
    @StateObject var serviceDelegate = ServiceDelegate()
    @State var showFileImporter = false
    @State var showInformationNote = false
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var appViewModel: ApplicationState
    
    let logger = Logger(subsystem: "join-keygen", category: "communication")
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onDisappear {
                viewModel.stopJoinKeygen()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.image],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleQrCodeFromImage(result: result)
            }
    }
    
    var states: some View {
        VStack {
            switch viewModel.status {
            case .DiscoverSessionID:
                discoveringSessionID
            case .DiscoverService:
                discoveringService
            case .JoinKeygen:
                joinKeygen
            case .WaitingForKeygenToStart:
                waitingForKeygenStart
            case .KeygenStarted:
                keygenStarted
            case .FailToStart:
                failToStartKeygen
            case .NoCameraAccess:
                cameraErrorView
            }
        }
        .padding()
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    var keygenStarted: some View {
        HStack {
            if viewModel.serverAddress != nil && self.viewModel.sessionID != nil {
                keygenView
            } else {
                keygenErrorText
            }
        }
        .padding(.vertical, 30)
    }
    
    var keygenView: some View {
        KeygenView(
            vault: self.viewModel.vault,
            tssType: self.viewModel.tssType,
            keygenCommittee: self.viewModel.keygenCommittee,
            vaultOldCommittee: self.viewModel.oldCommittee.filter { self.viewModel.keygenCommittee.contains($0) },
            mediatorURL: viewModel.serverAddress!,
            sessionID: self.viewModel.sessionID!,
            encryptionKeyHex: viewModel.encryptionKeyHex,
            oldResharePrefix: viewModel.oldResharePrefix, 
            fastSignConfig: nil
        )
    }
    
    var keygenErrorText: some View {
        Text(NSLocalizedString("failToStartKeygen", comment: "Unable to start key generation due to missing information"))
            .font(.body15MenloBold)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
    
    var failToStartKeygen: some View {
        VStack{
            Text(viewModel.errorMessage)
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
                .padding(.vertical, 30)
            
            filePicker
        }
    }
    
    var discoveringSessionID: some View {
        ProgressView()
            .preferredColorScheme(.dark)
            .onAppear {
                viewModel.showBarcodeScanner()
            }
    }
    
    var discoveringService: some View {
        VStack {
            Spacer()
            HStack {
                Text(NSLocalizedString("thisDevice", comment: "This device"))
                Text(self.viewModel.localPartyID)
            }
            
            HStack {
                Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
                
                if serviceDelegate.serverURL == nil {
                    ProgressView().progressViewStyle(.circular).padding(2)
                } else {
                    Image(systemName: "checkmark")
                        .onAppear {
                            viewModel.serverAddress = serviceDelegate.serverURL!
                            viewModel.setStatus(status: .JoinKeygen)
                        }
                }
            }
            Spacer()
            
            if showInformationNote {
                informationNote
            }
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(.vertical, 30)
        .onAppear {
            logger.info("Start to discover service")
            viewModel.discoverService()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                withAnimation {
                    showInformationNote = true
                }
            }
        }
    }
    
    var joinKeygen: some View {
        VStack {
            HStack {
                Text("thisDevice")
                Text(self.viewModel.localPartyID)
            }
            
            HStack {
                Text(NSLocalizedString("joinKeygen", comment: "Joining key generation, please wait..."))
                    .onAppear {
                        viewModel.joinKeygenCommittee()
                    }
            }
        }
        .font(.body15MenloBold)
        .multilineTextAlignment(.center)
        .padding(.vertical, 30)
    }
    
    var filePicker: some View {
        Button {
            showFileImporter.toggle()
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var waitingForKeygenStart: some View {
        VStack {
            HStack {
                Text("thisDevice")
                Text(self.viewModel.localPartyID)
            }
            
            HStack {
                Text(NSLocalizedString("waitingForKeygenStart", comment: "Waiting for key generation to start..."))
                ProgressView().progressViewStyle(.circular).padding(2)
            }
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(.vertical, 30)
        .task {
            await viewModel.waitForKeygenStart()
        }
    }
    
    var cameraErrorView: some View {
        NoCameraPermissionView()
    }
    
    var informationNote: some View {
        InformationNote()
            .padding(.bottom, 50)
            .padding(.horizontal, 15)
            .frame(height: showInformationNote ? nil : 0)
            .clipped()
            .padding(1)
    }
    
    private func setData() {
        viewModel.setData(
            vault: vault,
            serviceDelegate: self.serviceDelegate,
            vaults: vaults,
            isCameraPermissionGranted: appViewModel.isCameraPermissionGranted
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            viewModel.isShowingScanner = false
            viewModel.handleDeeplinkScan(deeplinkViewModel.receivedUrl)
        }
    }
}

#Preview {
    JoinKeygenView(vault: Vault.example)
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
}
