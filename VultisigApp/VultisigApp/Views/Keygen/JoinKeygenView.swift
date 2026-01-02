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
    let selectedVault: Vault?
    
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
            .if(viewModel.status == .KeygenStarted) {
                $0.ignoresSafeArea()
            }
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
        .if(viewModel.status != .KeygenStarted) {
            $0
                .padding()
                .cornerRadius(10)
        }        
    }
    
    @ViewBuilder
    var keygenStarted: some View {
        if viewModel.serverAddress != nil && self.viewModel.sessionID != nil {
            keygenView
                .ignoresSafeArea()
            #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
            #endif
        } else {
            keygenErrorText
                .padding(.vertical, 30)
        }
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
            keyImportInput: viewModel.keyImportInput,
            isInitiateDevice: false,
            hideBackButton: $hideBackButton
        )
    }
    
    var keygenErrorText: some View {
        Text(NSLocalizedString("failToStartKeygen", comment: "Unable to start key generation due to missing information"))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
    }
    
    var failToStartKeygen: some View {
        VStack{
            Text(viewModel.errorMessage)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
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
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.textPrimary)
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
                Text(":")
                Text(self.viewModel.localPartyID)
            }
            .padding(.bottom, 22)
            
            Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
        }
        .padding(22)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
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
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
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
    
    var vaultsMismatchedError: some View {
        SendCryptoVaultErrorView()
    }
    
    private func setData() {
        appViewModel.checkCameraPermission()
        loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
        
        viewModel.setData(
            vault: vault,
            selectedVault: selectedVault,
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
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.title1)
            
            Text(NSLocalizedString("joinKeygenViewDescription", comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
}

#Preview {
    JoinKeygenView(vault: Vault.example, selectedVault: Vault.example)
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
}
