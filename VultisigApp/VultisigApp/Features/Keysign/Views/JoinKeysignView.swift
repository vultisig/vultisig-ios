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
    @EnvironmentObject var appViewModelLegacy: AppViewModel
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

    var isInAnimationState: Bool {
        viewModel.status == .WaitingForKeysignToStart
            || viewModel.status == .KeysignStarted
            || viewModel.status == .QBTCClaim
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
                vaultMismatchErrorView
            case .KeysignSameDeviceShare:
                sameDeviceShareErrorView
            case .KeysignNoCameraAccess:
                NoCameraPermissionView()
            case .VaultTypeDoesntMatch:
                wrongVaultTypeErrorView
            case .QBTCClaim:
                if let driver = viewModel.qbtcClaimDriver {
                    QBTCClaimJoinView(driver: driver)
                } else {
                    keysignFailedText
                }
            }

        }
        .if(!isInAnimationState) { $0.padding().cornerRadius(10) }
    }

    var keysignStartedView: some View {
        ZStack {
            if viewModel.serverAddress != nil && !viewModel.sessionID.isEmpty {
                keysignView
            } else {
                Text(NSLocalizedString("unableToStartKeysignProcess", comment: ""))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
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
            isInitiateDevice: false,
            decodedFunctionName: viewModel.decodedFunctionName,
            decodedTokenAmount: viewModel.decodedTokenAmount,
            decodedTokenTicker: viewModel.decodedTokenTicker,
            decodedTokenLogo: viewModel.decodedTokenLogo,
            decodedTokenDisplay: viewModel.decodedTokenDisplay,
            decodedTokenIsUnlimited: viewModel.decodedTokenIsUnlimited,
            decodedFunctionSignature: viewModel.decodedFunctionSignature,
            decodedFunctionArguments: viewModel.decodedFunctionArguments
        )
    }

    var keysignFailedText: some View {
        let presentation = ErrorPresentation.signing(rawError: viewModel.errorMsg)
        return ErrorView(
            type: presentation.type,
            title: presentation.title,
            description: presentation.description,
            buttonTitle: "tryAgain".localized,
            rawError: presentation.rawError
        ) {
            appViewModelLegacy.restart()
        }
    }

    var vaultMismatchErrorView: some View {
        errorView(.vaultNotLoaded) {
            appViewModelLegacy.set(selectedVault: appViewModelLegacy.selectedVault, showingVaultSelector: true)
        }
    }

    var sameDeviceShareErrorView: some View {
        errorView(.sameVaultShare, buttonTitle: "goToHomeView".localized) {
            appViewModelLegacy.restart()
        }
    }

    var wrongVaultTypeErrorView: some View {
        errorView(.vaultTypeMismatch) {
            appViewModelLegacy.set(selectedVault: appViewModelLegacy.selectedVault, showingVaultSelector: true)
        }
    }

    func errorView(
        _ kind: ErrorPresentation.Kind,
        buttonTitle: String = "tryAgain".localized,
        action: @escaping () -> Void
    ) -> some View {
        let presentation = ErrorPresentation(kind)
        return ErrorView(
            type: presentation.type,
            title: presentation.title,
            description: presentation.description,
            buttonTitle: buttonTitle,
            rawError: presentation.rawError,
            action: action
        )
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
        .environmentObject(AppViewModel())
        .environmentObject(GlobalStateViewModel())
}

#if os(iOS)
import SwiftUI

extension JoinKeysignView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .if(!isInAnimationState) {
            $0
                .navigationTitle(NSLocalizedString(globalStateViewModel.showKeysignDoneView ? "transactionComplete" : "joinKeysign", comment: "Join Keysign"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                        NavigationHelpButton()
                    }
                }
        }
        .if(isInAnimationState) {
            $0.toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    var main: some View {
        if isInAnimationState {
            states
        } else {
            VStack {
                Spacer()
                states
                Spacer()
            }
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension JoinKeysignView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }

    @ViewBuilder
    var main: some View {
        if isInAnimationState {
            states
        } else {
            VStack {
                headerMac
                Spacer()
                states
                Spacer()
            }
        }
    }

    var headerMac: some View {
        JoinKeygenHeader(title: globalStateViewModel.showKeysignDoneView ? "transactionComplete" : "joinKeysign", hideBackButton: globalStateViewModel.showKeysignDoneView)
    }
}
#endif
