//
//  JoinKeygen.swift
//  VultisigApp

import Network
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import RiveRuntime

struct JoinKeygenView: View {
    let vault: Vault
    
    @Query var vaults: [Vault]
    
    @StateObject var viewModel = JoinKeygenViewModel()
    @StateObject var serviceDelegate = ServiceDelegate()
    @State var showFileImporter = false
    @State var showInformationNote = false
    @State var hideBackButton: Bool = false
    
    @State var loadingAnimationVM: RiveViewModel? = nil
    
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
            fastSignConfig: nil,
            isInitiateDevice: false,
            hideBackButton: $hideBackButton
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
            card
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
    
    var card: some View {
        VStack(spacing: 12) {
            if serviceDelegate.serverURL == nil {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Image(systemName: "checkmark")
                    .onAppear {
                        viewModel.serverAddress = serviceDelegate.serverURL!
                        viewModel.setStatus(status: .JoinKeygen)
                    }
            }
            
            HStack {
                Text(NSLocalizedString("thisDevice", comment: "This device"))
                Text(self.viewModel.localPartyID)
            }
            .padding(.bottom, 22)
            
            Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
        }
        .padding(22)
        .background(Color.blue600)
        .cornerRadius(12)
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(.alertTurquoise)
            .opacity(0.05)
            .blur(radius: 20)
    }
    
    var joinKeygen: some View {
        VStack(spacing: 26) {
            capsule
            joiningKeygenCardContent
            animation
        }
        .padding(.vertical, 30)
        .onAppear {
            viewModel.joinKeygenCommittee()
        }
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
        VStack(spacing: 26) {
            capsule
            waitingForKeygenCardContent
            animation
        }
        .padding(.vertical, 30)
        .task {
            await viewModel.waitForKeygenStart()
        }
    }
    
    var capsule: some View {
        IconCapsule(title: "secureVault", icon: "shield")
    }
    
    var joiningKeygenCardContent: some View {
        getKeygenCardContent("joiningKeygen")
    }
    
    var waitingForKeygenCardContent: some View {
        getKeygenCardContent("joinKeygenViewTitle")
    }
    
    var animation: some View {
        loadingAnimationVM?.view()
            .frame(width: 24, height: 24)
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
        appViewModel.checkCameraPermission()
        loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
        
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
    
    private func getKeygenCardContent(_ title: String) -> some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.neutral0)
                .font(.body28BrockmannMedium)
            
            Text(NSLocalizedString("joinKeygenViewDescription", comment: ""))
                .foregroundColor(.extraLightGray)
                .font(.body14BrockmannMedium)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
}

#Preview {
    JoinKeygenView(vault: Vault.example)
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
}
