//
//  PeerDiscoveryScreen.swift
//  VultisigApp
//

import SwiftUI
import RiveRuntime

struct PeerDiscoveryScreen: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState
    let fastSignConfig: FastSignConfig?
    let keyImportInput: KeyImportInput?
    let setupType: KeyImportSetupType?

    init(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        fastSignConfig: FastSignConfig?,
        keyImportInput: KeyImportInput? = nil,
        setupType: KeyImportSetupType? = nil
    ) {
        self.tssType = tssType
        self.vault = vault
        self.selectedTab = selectedTab
        self.fastSignConfig = fastSignConfig
        self.keyImportInput = keyImportInput
        self.setupType = setupType
    }

    @StateObject var viewModel = KeygenPeerDiscoveryViewModel()
    @StateObject var participantDiscovery = ParticipantDiscovery()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    @State var qrCodeImage: Image? = nil

    @State var showInfoSheet: Bool = false
    @State var hideBackButton: Bool = false

    @State var screenWidth: CGFloat = .zero
    @State var screenHeight: CGFloat = .zero

    @State var dotsIndicatorVM: RiveViewModel? = nil

    @Environment(\.displayScale) var displayScale

#if os(iOS)
    @State var orientation = UIDevice.current.orientation
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
#endif

    var localModeAvailable: Bool { tssType != .KeyImport }

    var isShareButtonVisible: Bool {
        viewModel.status == .WaitingForDevices && selectedTab.hasOtherDevices
    }

    var qrCodeSize: CGFloat {
#if os(iOS)
        screenHeight / 3.5
#else
        min(screenWidth / 2.5, screenHeight / 2.5)
#endif
    }

    var totalDeviceCount: Int {
        switch tssType {
        case .Reshare:
            return vault.signers.count
        case .Migrate:
            return vault.signers.count
        case .KeyImport, .Keygen:
            if let setupType {
                switch setupType {
                case .fast:
                    return 2
                case .secure(let numberOfDevices):
                    return numberOfDevices
                }
            }
            return 2
        }
    }

    var isFixedDeviceMode: Bool {
        totalDeviceCount <= 3
    }

    var badgeTotalCount: Int? {
        isFixedDeviceMode ? totalDeviceCount : nil
    }

    var minRequiredDevices: Int { 4 }

    func thresholdForCount(_ count: Int) -> Int {
        Int(ceil(Double(count) * 2.0 / 3.0))
    }

    var openEndedButtonTitle: String {
        let count = viewModel.selections.count
        if count < minRequiredDevices {
            let remaining = minRequiredDevices - count
            return String(format: NSLocalizedString("addAtLeastNMoreDevices", comment: ""), remaining)
        }
        let threshold = thresholdForCount(count)
        return String(format: NSLocalizedString("continueThresholdOfTotal", comment: ""), threshold, count)
    }

    var isOpenEndedContinueDisabled: Bool {
        switch viewModel.tssType {
        case .Migrate:
            return Set(viewModel.selections) != Set(viewModel.vault.signers)
        default:
            return viewModel.selections.count < minRequiredDevices
        }
    }

    var isInternetMode: Bool {
        viewModel.selectedNetwork == .Internet
    }

    var body: some View {
        GeometryReader { proxy in
            Screen(
                showNavigationBar: false,
                edgeInsets: ScreenEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                backgroundType: .gradient
            ) {
                states
            }
            .onAppear {
                screenWidth = proxy.size.width
                screenHeight = proxy.size.height
                setData()
            }
#if os(macOS)
            .onChange(of: proxy.size.width) { _, _ in
                screenWidth = proxy.size.width
            }
            .onChange(of: proxy.size.height) { _, _ in
                screenHeight = proxy.size.height
            }
#endif
        }
        .if(viewModel.status == .WaitingForDevices) {
            $0.crossPlatformToolbar("", showsBackButton: !hideBackButton) {
                CustomToolbarItem(placement: .trailing) {
                    if isShareButtonVisible {
                        NavigationQRShareButton(
                            vault: vault,
                            type: .Keygen,
                            viewModel: shareSheetViewModel
                        )
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(hideBackButton)
#if os(iOS)
        .detectOrientation($orientation)
        .onChange(of: orientation) { _, _ in
            setData()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
#endif
        .onLoad {
            viewModel.setData(
                vault: vault,
                tssType: tssType,
                state: selectedTab,
                participantDiscovery: participantDiscovery,
                fastSignConfig: fastSignConfig,
                chains: keyImportInput?.chains
            )
            setData()
            viewModel.startDiscovery()
            if selectedTab == .fast {
                hideBackButton = true
            }
        }
        .onDisappear {
            viewModel.stopMediator()
        }
        .onLoad {
            showInfo()
        }
        .crossPlatformSheet(isPresented: $showInfoSheet) {
            PeerDiscoveryInfoBanner(isPresented: $showInfoSheet)
        }
        .onChange(of: viewModel.selectedNetwork) {
            viewModel.restartParticipantDiscovery()
            qrCodeImage = nil
            setData()
        }
        .onChange(of: viewModel.selections) {
            autoStartKeygenIfReady()
        }
    }

    var states: some View {
        VStack {
            switch (viewModel.status, selectedTab.hasOtherDevices) {
            case (.WaitingForDevices, false):
                if viewModel.isLookingForDevices {
                    lookingForDevices
                } else {
                    keygenView
                }
            case (.WaitingForDevices, true):
                waitingForDevices
            case (.Keygen, _):
                keygenView
            case (.Failure, _):
                failureText
            }
        }
        .foregroundColor(Theme.colors.textPrimary)
        .blur(radius: showInfoSheet ? 1 : 0)
        .animation(.easeInOut, value: showInfoSheet)
    }

    var waitingForDevices: some View {
        VStack(spacing: 0) {
            portraitContent
            bottomButton
            switchLink
                .showIf(localModeAvailable)
        }
    }

    var portraitContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 32) {
                    pairingBarcode
                    statusText
                }
                .padding(.bottom, 8)
                deviceList
            }
        }
    }

    var pairingBarcode: some View {
        qrCodeImage?
            .resizable()
            .frame(maxWidth: qrCodeSize, maxHeight: qrCodeSize)
            .padding(20)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(33)
            .overlay(
                RoundedRectangle(cornerRadius: 33)
                    .stroke(
                        isInternetMode
                        ? AnyShapeStyle(LinearGradient.qrBorderGradient)
                        : AnyShapeStyle(Theme.colors.borderLight),
                        lineWidth: 8
                    )
            )
    }

    var statusText: some View {
        VStack(spacing: 4) {
            let description = isInternetMode ? "waitingForDevicesToConnect" : "localModeWaitingOnDevices"
            HStack(alignment: .bottom, spacing: 2) {
                Text(description.localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)

                dotsIndicatorAnimation
                    .offset(y: 2)
            }
            .onAppear {
                dotsIndicatorVM = RiveViewModel(fileName: "dots_indicator", autoPlay: true)
            }
            .onDisappear {
                dotsIndicatorVM?.stop()
            }

            // TODO: - Add local mode description if needed
            //                Text(NSLocalizedString("localModeDescription", comment: ""))
            //                    .font(Theme.fonts.caption12)
            //                    .foregroundStyle(Theme.colors.textTertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
    }

    var dotsIndicatorAnimation: some View {
        dotsIndicatorVM?.view()
            .frame(width: 12, height: 12)
    }

    var deviceList: some View {
        VStack(spacing: 12) {
#if os(iOS)
            PeerCell(
                id: idiom == .phone ? "iPhone" : "iPad",
                isThisDevice: true,
                index: 1,
                totalCount: badgeTotalCount
            )
#else
            PeerCell(
                id: "Mac",
                isThisDevice: true,
                index: 1,
                totalCount: badgeTotalCount
            )
#endif

            devices

            if let nextEmptyIndex = nextEmptySlotIndex {
                EmptyPeerCell(
                    index: nextEmptyIndex,
                    totalCount: badgeTotalCount
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.selections)
        .frame(maxWidth: .infinity)
#if os(iOS)
        .padding(.horizontal, idiom == .pad ? 24 : 16)
#else
        .padding(.horizontal, 24)
        .padding(.top, 8)
#endif
    }

    var devices: some View {
        ForEach(
            Array(participantDiscovery.peersFound.enumerated()),
            id: \.element
        ) { offset, peer in
            Button {
                viewModel.handleSelection(peer)
            } label: {
                PeerCell(
                    id: peer,
                    isSelected: viewModel.selections.contains(peer),
                    index: offset + 2,
                    totalCount: badgeTotalCount
                )
            }
        }
    }

    var nextEmptySlotIndex: Int? {
        let filledCount = 1 + participantDiscovery.peersFound.count
        if isFixedDeviceMode {
            guard filledCount < totalDeviceCount else { return nil }
            return filledCount + 1
        } else {
            return filledCount + 1
        }
    }

    @ViewBuilder
    var bottomButton: some View {
        if isFixedDeviceMode {
            EmptyView()
        } else {
            PrimaryButton(title: openEndedButtonTitle) {
                viewModel.startKeygen()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
#if os(iOS)
            .padding(.bottom, idiom == .phone ? 10 : 30)
#else
            .padding(.bottom, 10)
#endif
            .disabled(isOpenEndedContinueDisabled)
            .animation(.easeInOut(duration: 0.2), value: isOpenEndedContinueDisabled)
        }
    }

    var switchLink: some View {
        SwitchToLocalLink(isForKeygen: true, selectedNetwork: $viewModel.selectedNetwork)
            .disabled(viewModel.isLoading)
#if os(macOS)
            .padding(.bottom, 24)
#endif
    }

    var lookingForDevices: some View {
        KeygenAnimationView(
            isFast: selectedTab == .fast,
            connected: .constant(false),
            progress: .constant(0)
        )
    }

    func autoStartKeygenIfReady() {
        guard isFixedDeviceMode,
              viewModel.selections.count >= totalDeviceCount,
              viewModel.status == .WaitingForDevices else {
            return
        }
        viewModel.startKeygen()
    }

    func disableContinueButton() -> Bool {
        switch viewModel.tssType {
        case .Keygen:
            switch selectedTab {
            case .fast:
                return viewModel.selections.count < 2
            case .active:
                return viewModel.selections.count < 3
            case .secure:
                return viewModel.selections.count < 2
            }
        case .Reshare:
            let requiredCount = vault.getThreshold() + 1
            return viewModel.selections.count < requiredCount
        case .Migrate:
            return Set(viewModel.selections) != Set(viewModel.vault.signers)
        case .KeyImport:
            return showWaitingOnDevice
        }
    }

    var showWaitingOnDevice: Bool {
        guard
            let setupType,
            case let .secure(numberOfDevices) = setupType
        else {
            return false
        }

        switch numberOfDevices {
        case 0...3:
            return viewModel.selections.count != numberOfDevices
        default:
            return viewModel.selections.count < numberOfDevices
        }
    }

    var keygenView: some View {
        KeygenView(
            vault: viewModel.vault,
            tssType: tssType,
            keygenCommittee: viewModel.keygenCommittee,
            vaultOldCommittee: viewModel.vault.signers.filter { viewModel.selections.contains($0) },
            mediatorURL: viewModel.serverAddr,
            sessionID: viewModel.sessionID,
            encryptionKeyHex: viewModel.encryptionKeyHex ?? "",
            oldResharePrefix: viewModel.vault.resharePrefix ?? "",
            fastSignConfig: fastSignConfig,
            keyImportInput: keyImportInput,
            isInitiateDevice: true,
            hideBackButton: $hideBackButton
        )
    }

    var failureText: some View {
        VStack {
            Text(self.viewModel.errorMessage)
                .font(Theme.fonts.bodyMMedium)
                .multilineTextAlignment(.center)
                .foregroundColor(.red)
        }
    }

    private func showInfo() {
        guard selectedTab == .secure else {
            showInfoSheet = false
            return
        }

        switch self.tssType {
        case .Keygen:
            showInfoSheet = true
        case .Reshare:
            showInfoSheet = false
        case .Migrate:
            showInfoSheet = false
        case .KeyImport:
            showInfoSheet = false
        }
    }

    func setData() {
#if os(iOS)
        guard self.qrCodeImage == nil, qrCodeSize > 0 else { return }
        guard let (qrCodeString, qrCodeImage) = viewModel.getQRCodeData(
            size: qrCodeSize, displayScale: displayScale
        ) else {
            return
        }
#else
        guard let (qrCodeString, qrCodeImage) = viewModel.getQRCodeData(
            size: 500, displayScale: displayScale
        ) else {
            return
        }
#endif

        self.qrCodeImage = qrCodeImage
        shareSheetViewModel.render(
            qrCodeImage: qrCodeImage,
            qrCodeData: qrCodeString,
            displayScale: displayScale,
            type: .Keygen
        )
    }
}

#Preview {
    PeerDiscoveryScreen(tssType: .Keygen, vault: Vault.example, selectedTab: .fast, fastSignConfig: nil)
}
