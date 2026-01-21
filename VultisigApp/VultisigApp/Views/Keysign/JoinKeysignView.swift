//
//  JoinKeysignView.swift
//  VultisigApp

import SwiftUI

struct JoinKeysignView: View {
    let vault: Vault

    @StateObject private var serviceDelegate = ServiceDelegate()
    @StateObject var viewModel = JoinKeysignViewModel()

    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var appViewModel: ApplicationState
    @EnvironmentObject var globalStateViewModel: GlobalStateViewModel

    var body: some View {
        content
            .onLoad {
                setData()
            }
            .task {
                do {
                    _ = try await ThorchainService.shared.getTHORChainChainID()
                } catch {
                    print("fail to get thorchain network id, \(error.localizedDescription)")
                }
            }
    }

    var states: some View {
        ZStack {
            switch viewModel.status {
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
            case .VaultMismatch:
                KeysignVaultMismatchErrorView()
            case .KeysignSameDeviceShare:
                KeysignSameDeviceShareErrorView()
            case .KeysignNoCameraAccess:
                NoCameraPermissionView()
            case .VaultTypeDoesntMatch:
                KeysignWrongVaultTypeErrorView()
            }

        }
        .padding()
        .cornerRadius(10)
    }

    var keysignStartedView: some View {
        ZStack {
            if viewModel.serverAddress != nil && !viewModel.sessionID.isEmpty {
                keysignView
            } else {
                Text(NSLocalizedString("unableToStartKeysignProcess", comment: ""))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
    }

    var keysignView: some View {
        let keysignType: KeyType
        if let keysignPayload = viewModel.keysignPayload {
            keysignType = keysignPayload.coin.chain.signingKeyType
        } else if let customMessagePayload = viewModel.customMessagePayload,
                  let chain = Chain.allCases.first(where: { $0.name.caseInsensitiveCompare(customMessagePayload.chain) == .orderedSame }) {
            keysignType = chain.signingKeyType
        } else {
            keysignType = .ECDSA
        }

        return KeysignView(
            vault: viewModel.vault,
            keysignCommittee: viewModel.keysignCommittee,
            mediatorURL: viewModel.serverAddress ?? "",
            sessionID: viewModel.sessionID,
            keysignType: keysignType,
            messsageToSign: viewModel.keysignMessages,
            keysignPayload: viewModel.keysignPayload,
            customMessagePayload: viewModel.customMessagePayload,
            transferViewModel: nil,
            encryptionKeyHex: viewModel.encryptionKeyHex,
            isInitiateDevice: false
        )
    }

    var keysignFailedText: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("keysignFail", comment: "Failed to start the keysign process"))
            Text(viewModel.errorMsg)
        }
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.textPrimary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
    }

    var keysignMessageConfirm: some View {
        ZStack {
            if viewModel.keysignPayload?.swapPayload != nil {
                // Check if it's an LP operation by looking at the memo
                if let memo = viewModel.keysignPayload?.memo, memo.starts(with: "+:") || memo.starts(with: "-:") {
                    // LP operation - show regular message confirm instead of swap
                    KeysignMessageConfirmView(viewModel: viewModel)
                } else {
                    // Regular swap
                    KeysignSwapConfirmView(viewModel: viewModel)
                }
            } else if viewModel.customMessagePayload != nil {
                KeysignCustomMessageConfirmView(viewModel: viewModel)
            } else {
                KeysignMessageConfirmView(viewModel: viewModel)
            }
        }
    }

    var waitingForKeySignStart: some View {
        KeysignStartView(viewModel: viewModel)
    }

    var discoveringSignMessage: some View {
        Loader()
            .onLoad {
                viewModel.startScan()
            }
    }

    var discoverService: some View {
        KeysignDiscoverServiceView(viewModel: viewModel, serviceDelegate: serviceDelegate)
    }

    private func setData() {
        appViewModel.checkCameraPermission()

        viewModel.setData(
            vault: vault,
            serviceDelegate: serviceDelegate,
            isCameraPermissionGranted: appViewModel.isCameraPermissionGranted
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            viewModel.isShowingScanner = false
            viewModel.handleDeeplinkScan(deeplinkViewModel.receivedUrl)
        }
    }
}

#Preview {
    JoinKeysignView(vault: Vault.example)
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
        .environmentObject(GlobalStateViewModel())
}
