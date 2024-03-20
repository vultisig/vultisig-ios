//
//  JoinKeygen.swift
//  VoltixApp

import CodeScanner
import Network
import OSLog
import SwiftUI

struct JoinKeygenView: View {
    private let logger = Logger(subsystem: "join-keygen", category: "communication")
    let vault: Vault
    @StateObject var viewModel = JoinKeygenViewModel()
    @StateObject var serviceDelegate = ServiceDelegate()
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var body: some View {
        ZStack {
            background
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
                }
            }
            .padding()
            .cornerRadius(10)
            .shadow(radius: 5)
        }
        .sheet(isPresented: $viewModel.isShowingScanner, content: {
            CodeScannerView(codeTypes: [.qr], completion: self.viewModel.handleScan)
        })
        .navigationTitle(NSLocalizedString("joinKeygen", comment: "Join keygen / reshare"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
        .onAppear {
            viewModel.setData(vault: vault, serviceDelegate: self.serviceDelegate)
        }
        .onDisappear {
            viewModel.stopJoinKeygen()
        }
    }
    
    var scanButton: some View {
        ZStack {
            Circle()
                .foregroundColor(.blue800)
                .frame(width: 80, height: 80)
                .opacity(0.8)
            
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
    }
    
    var keygenStarted: some View {
        HStack {
            if serviceDelegate.serverURL != nil && self.viewModel.sessionID != nil {
                KeygenView(vault: vault,
                           tssType: self.viewModel.tssType,
                           keygenCommittee: self.viewModel.keygenCommittee,
                           vaultOldCommittee: self.viewModel.oldCommittee.filter { self.viewModel.keygenCommittee.contains($0) },
                           mediatorURL: serviceDelegate.serverURL!,
                           sessionID: self.viewModel.sessionID!)
            } else {
                Text(NSLocalizedString("failToStartKeygen", comment: "Unable to start key generation due to missing information"))
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 30)
    }
    
    var failToStartKeygen: some View {
        HStack {
            Text(viewModel.errorMessage)
                .font(.body15MenloBold)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
    }
    
    var discoveringSessionID: some View {
        VStack {
            Text(NSLocalizedString("scanQRCodeJoinKeygen", comment: "Scan the barcode on another VoltixApp device to start"))
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
            
            Button(action: {
                viewModel.showBarcodeScanner()
            }) {
                scanButton
            }
        }
    }
    
    var discoveringService: some View {
        VStack {
            HStack {
                Text("thisDevice")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                Text(self.viewModel.localPartyID)
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
                    .foregroundColor(.neutral0)
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                
                if serviceDelegate.serverURL == nil {
                    ProgressView().progressViewStyle(.circular).padding(2)
                } else {
                    Image(systemName: "checkmark").onAppear {
                        viewModel.setStatus(status: .JoinKeygen)
                    }
                }
            }
        }.padding(.vertical, 30)
            .onAppear {
                logger.info("Start to discover service")
                viewModel.discoverService()
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
                    .font(.body15MenloBold)
                    .multilineTextAlignment(.center)
                    .onAppear {
                        viewModel.joinKeygenCommittee()
                    }
            }
        }.padding(.vertical, 30)
    }
    
    var waitingForKeygenStart: some View {
        VStack {
            HStack {
                Text("thisDevice")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            
                Text(self.viewModel.localPartyID)
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Text(NSLocalizedString("waitingForKeygenStart", comment: "Waiting for key generation to start..."))
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                ProgressView().progressViewStyle(.circular).padding(2)
            }
        }
        .padding(.vertical, 30)
        .task {
            await viewModel.waitForKeygenStart()
        }
    }
}

struct JoinKeygenView_Previews: PreviewProvider {
    static var previews: some View {
        JoinKeygenView(vault: Vault.example)
    }
}
