//
//  JoinKeysignView.swift
//  VoltixApp

import CodeScanner
import OSLog
import SwiftUI

struct JoinKeysignView: View {
    let vault: Vault
       
    @StateObject private var serviceDelegate = ServiceDelegate()
    @StateObject var viewModel = JoinKeysignViewModel()
    
    let logger = Logger(subsystem: "join-keysign", category: "communication")

    var body: some View {
        ZStack {
            background
            states
        }
        .navigationTitle(NSLocalizedString("joinKeySign", comment: "Join Keysign"))
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
        .sheet(isPresented: $viewModel.isShowingScanner, content: {
            CodeScannerView(codeTypes: [.qr], completion: self.viewModel.handleScan)
        })
        .onAppear {
            self.viewModel.setData(vault: self.vault, serviceDelegate: self.serviceDelegate)
        }
        .onDisappear(){
            self.viewModel.stopJoiningKeysign()
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var states: some View {
        VStack {
            switch self.viewModel.status {
            case .DiscoverSigningMsg:
                discoveringSignMessage
            case .DiscoverService:
                discoverService
            case .JoinKeysign:
                keysignMessageConfirm
            case .WaitingForKeysignToStart:
                waitingForKeySignStart
            case .KeysignStarted:
                keysignStartedView
            case .FailedToStart:
                keysignFailedText
            }
        }
        .padding()
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    var keysignStartedView: some View {
        HStack {
            if self.serviceDelegate.serverURL != nil && !self.viewModel.sessionID.isEmpty {
                keysignView
            } else {
                Text("Unable to start the keysign process due to missing information.")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
    }
    
    var keysignView: some View {
        KeysignView(
            vault: self.vault,
            keysignCommittee: self.viewModel.keysignCommittee,
            mediatorURL: self.serviceDelegate.serverURL ?? "",
            sessionID: self.viewModel.sessionID,
            keysignType: self.viewModel.keysignPayload?.coin.chain.signingKeyType ?? .ECDSA,
            messsageToSign: self.viewModel.keysignMessages,
            keysignPayload: self.viewModel.keysignPayload
        )
    }
    
    var keysignFailedText: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("keysignFail", comment: "Failed to start the keysign process"))
            Text(self.viewModel.errorMsg)
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
    }
    
    var keysignMessageConfirm: some View {
        VStack(alignment: .leading) {
            Text("Confirm to sign the message?")
                .frame(maxWidth: .infinity)
            
            Separator()
            
            HStack {
                Text("To: ")
                Text("\(self.viewModel.keysignPayload?.toAddress ?? "")")
            }
            .padding(.vertical)
            
            Text("Amount: \(String(self.viewModel.keysignPayload?.toAmount ?? 0))")
                .padding(.vertical)
            
            Spacer()
            
            Button(action: {
                self.viewModel.joinKeysignCommittee()
            }) {
                FilledButton(title: "joinKeySign")
            }
        }
    }

    var waitingForKeySignStart: some View {
        VStack(spacing: 16) {
            ProgressView()
                .preferredColorScheme(.dark)
            
            HStack {
                Text("thisDevice")
                Text(self.viewModel.localPartyID)
            }
            
            Text(NSLocalizedString("waitingForKeySignStart", comment: "Waiting for the keysign process to start"))
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(30)
        .background(Color.blue600)
        .cornerRadius(10)
        .task {
            await self.viewModel.waitForKeysignStart()
        }
    }
    
    var discoveringSignMessage: some View {
        VStack(spacing: 24) {
            Text(NSLocalizedString("scanQRCodeJoinKeygen", comment: "Scan the barcode on another VoltixApp device to start"))
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Button(action: {
                viewModel.startScan()
            }) {
                scanButton
            }
        }
    }
    
    var discoverService: some View {
        VStack(spacing: 16) {
            ZStack {
                if self.serviceDelegate.serverURL == nil {
                    ProgressView()
                        .preferredColorScheme(.dark)
                } else {
                    Image(systemName: "checkmark").onAppear {
                        self.viewModel.setStatus(status: .JoinKeysign)
                    }
                }
            }
            .padding(.bottom, 18)
            
            HStack {
                Text(NSLocalizedString("thisDevice", comment: ""))
                Text(self.viewModel.localPartyID)
            }
            
            Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(30)
        .background(Color.blue600)
        .cornerRadius(10)
        .onAppear {
            self.viewModel.discoverService()
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
    JoinKeysignView(vault: Vault.example)
}
