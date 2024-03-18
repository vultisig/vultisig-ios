//
//  JoinKeysignView.swift
//  VoltixApp

import CodeScanner
import OSLog
import SwiftUI

struct JoinKeysignView: View {
    let vault: Vault
    private let logger = Logger(subsystem: "join-keysign", category: "communication")
       
    @StateObject private var serviceDelegate = ServiceDelegate()
    @StateObject var viewModel = JoinKeysignViewModel()
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            self.background
            VStack {
                switch self.viewModel.status {
                case .DiscoverSigningMsg:
                    self.discoveringSignMessage
                case .DiscoverService:
                    self.discoverService
                case .JoinKeysign:
                    self.keysignMessageConfirm
                case .WaitingForKeysignToStart:
                    self.waitingForKeySignStart
                case .KeysignStarted:
                    HStack {
                        if self.serviceDelegate.serverURL != nil && !self.viewModel.sessionID.isEmpty {
                            KeysignView(vault: self.vault,
                                        keysignCommittee: self.viewModel.keysignCommittee,
                                        mediatorURL: self.serviceDelegate.serverURL ?? "",
                                        sessionID: self.viewModel.sessionID,
                                        keysignType: self.viewModel.keysignPayload?.coin.chain.signingKeyType ?? .ECDSA,
                                        messsageToSign: self.viewModel.keysignMessages,
                                        keysignPayload: self.viewModel.keysignPayload)
                        } else {
                            Text("Unable to start the keysign process due to missing information.")
                                .font(.body15MenloBold)
                                .multilineTextAlignment(.center)
                        }
                    }.navigationBarBackButtonHidden(true)
                case .FailedToStart:
                    VStack {
                        Text(NSLocalizedString("keysignFail", comment: "Failed to start the keysign process"))
                            .font(.body15MenloBold)
                            .multilineTextAlignment(.center)
                        Text(self.viewModel.errorMsg).font(.body15MenloBold)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .cornerRadius(10)
            .shadow(radius: 5)
        }
        .navigationTitle(NSLocalizedString("joinKeySign", comment: "Join Keysign"))
        .sheet(isPresented: $viewModel.isShowingScanner, content: {
            CodeScannerView(codeTypes: [.qr], completion: self.viewModel.handleScan)
        })
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
        }
        .onAppear {
            self.viewModel.setData(vault: self.vault, serviceDelegate: self.serviceDelegate)
        }
    }
    
    var keysignMessageConfirm: some View {
        VStack(alignment: .leading) {
            VStack {
                VStack(alignment: .center) {
                    Text("Confirm to sign the message?")
                        .font(.body15MenloBold)
                        .foregroundColor(.neutral0)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            HStack {
                Text("To: ")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                
                Text("\(self.viewModel.keysignPayload?.toAddress ?? "")")
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical)
            
            Text("Amount: \(String(self.viewModel.keysignPayload?.toAmount ?? 0))")
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
                .padding(.vertical)
            
            VStack {
                VStack(alignment: .center) {
                    Button(action: {
                        self.viewModel.joinKeysignCommittee()
                    }) {
                        FilledButton(title: "joinKeySign")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .padding(.vertical, 15)
        }
    }

    var waitingForKeySignStart: some View {
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
                Text(NSLocalizedString("waitingForKeySignStart", comment: "Waiting for the keysign process to start"))
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(2)
            }
        }.task {
            await self.viewModel.waitForKeysignStart()
        }
    }
    
    var discoveringSignMessage: some View {
        VStack {
            Text(NSLocalizedString("scanQRCodeJoinKeygen", comment: "Scan the barcode on another VoltixApp device to start"))
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
            
            Button(action: {
                self.viewModel.startScan()
            }) {
                self.scanButton
            }
        }
    }
    
    var discoverService: some View {
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
                
                if self.serviceDelegate.serverURL == nil {
                    ProgressView().progressViewStyle(.circular).padding(2)
                } else {
                    Image(systemName: "checkmark").onAppear {
                        self.viewModel.setStatus(status: .JoinKeysign)
                    }
                }
            }
        }.padding(.vertical, 30)
            .onAppear {
                self.viewModel.discoverService()
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
}

#Preview {
    JoinKeysignView(vault: Vault.example)
}
