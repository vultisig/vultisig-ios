//
//  Keygen.swift
//  VoltixApp
//

import CryptoKit
import Foundation
import Mediator
import OSLog
import SwiftData
import SwiftUI
import Tss

struct KeygenView: View {
    private let logger = Logger(subsystem: "keygen", category: "tss")
    @Environment(\.modelContext) private var context
    let vault: Vault
    let tssType: TssType // keygen or reshare
    let keygenCommittee: [String]
    let vaultOldCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    @StateObject var viewModel = KeygenViewModel()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack {
                    Spacer()
                    VStack(alignment: .center) {
                        switch viewModel.status {
                        case .CreatingInstance:
                            StatusText(status: NSLocalizedString("preparingVault", comment: "PREPARING VAULT..."))
                        case .KeygenECDSA:
                            StatusText(status: NSLocalizedString("generatingECDSA", comment: "GENERATING ECDSA KEY"))
                        case .KeygenEdDSA:
                            StatusText(status: NSLocalizedString("generatingEdDSA", comment: "GENERATING EdDSA KEY"))
                        case .ReshareECDSA:
                            StatusText(status: NSLocalizedString("reshareECDSA", comment: "Resharing ECDSA KEY"))
                        case .ReshareEdDSA:
                            StatusText(status: NSLocalizedString("reshareEdDSA", comment: "Resharing EdDSA KEY"))
                        case .KeygenFinished:
                            Text("DONE")
                                .font(.body15MenloBold)
                                .foregroundColor(.neutral0)
                                .multilineTextAlignment(.center)
                                .onAppear {
                                    viewModel.delaySwitchToMain()
                                }

                        case .KeygenFailed:
                            keygenFailedView
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height * 0.8)
                    Spacer()
                    WifiBar()
                }
            }
        }
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $viewModel.isLinkActive) {
            HomeView()
        }
        .task {
            await viewModel.startKeygen(context: context)
        }
    }

    var keygenFailedView: some View {
        switch tssType {
        case .Keygen:
            HStack {
                Text(NSLocalizedString("keygenFailed", comment: "key generation failed"))
                Text(viewModel.keygenError)
            }
        case .Reshare:
            HStack {
                Text(NSLocalizedString("reshareFailed", comment: "Resharing key failed"))
                Text(viewModel.keygenError)
            }
        }
    }
}

private struct StatusText: View {
    let status: String
    var body: some View {
        HStack {
            Text(self.status)
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)

            ProgressView()
                .progressViewStyle(.circular)
                .padding(2)
        }
    }
}

#Preview("keygen") {
    KeygenView(vault: Vault.example,
               tssType: .Keygen,
               keygenCommittee: [],
               vaultOldCommittee: [],
               mediatorURL: "",
               sessionID: "")
}
