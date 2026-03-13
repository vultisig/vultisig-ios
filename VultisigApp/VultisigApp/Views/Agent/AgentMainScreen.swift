//
//  AgentMainView.swift
//  VultisigApp
//

import SwiftUI

struct AgentMainScreen: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @StateObject private var viewModel = AgentChatViewModel()
    @Environment(\.router) private var router

    @State private var inputText = ""
    @State private var password = ""
    @State private var isAuthorizing = false
    @State private var authError: String?
    @State private var showDeleteConfirm = false
    @FocusState private var isInputFocused: Bool
    @FocusState private var isPasswordFocused: Bool

    private var isAuthorized: Bool {
        viewModel.isConnected && !viewModel.passwordRequired
    }

    private var hasActiveChat: Bool {
        !viewModel.messages.isEmpty || viewModel.isLoading
    }

    var body: some View {
        Screen(edgeInsets: .zero, backgroundType: .clear) {
            VStack(spacing: 0) {
                header
                ZStack {
                    if hasActiveChat {
                        chatContent
                    } else {
                        heroContent
                    }
                }
                bottomBar
            }
            .padding(.bottom, 16)
        }
        .background(background)
        .onAppear { checkAuth() }
        .onReceive(NotificationCenter.default.publisher(for: .agentDidSelectConversation)) { notif in
            if let id = notif.object as? String {
                loadConversation(id: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentDidAcceptTx)) { notif in
            guard let tx = notif.object as? AgentTxReady, let vault = appViewModel.selectedVault else { return }
            viewModel.acceptTxProposal(tx, vault: vault)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentDidRejectTx)) { notif in
            guard let tx = notif.object as? AgentTxReady, let vault = appViewModel.selectedVault else { return }
            viewModel.rejectTxProposal(tx, vault: vault)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentDidBroadcastTx)) { notif in
            if let txid = notif.userInfo?["txid"] as? String, let vault = appViewModel.selectedVault {
                viewModel.handleTxBroadcasted(txid: txid, vault: vault)
            }
        }
        .onChange(of: viewModel.passwordRequired) { _, required in
            if required {
                password = ""
                authError = nil
            }
        }
        .confirmationDialog(
            "agentDeleteConversationTitle".localized,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("delete".localized, role: .destructive) {
                deleteCurrentConversation()
            }
            Button("cancel".localized, role: .cancel) {}
        } message: {
            Text("agentDeleteConversationMessage".localized)
        }
        .alert("error".localized, isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("ok".localized) { viewModel.dismissError() }
        } message: {
            Text(viewModel.error ?? "")
        }
        .withLoading(text: "pleaseWait".localized, isLoading: $isAuthorizing)
        .sheet(isPresented: $viewModel.shouldShowPairingSheet) {
            if let tx = viewModel.pendingSendTx, let vault = appViewModel.selectedVault, let keysignPayload = viewModel.activeKeysignPayload {
                NavigationStack {
                    SendPairScreen(
                        vault: vault,
                        tx: tx,
                        keysignPayload: keysignPayload,
                        fastVaultPassword: tx.fastVaultPassword.nilIfEmpty
                    )
                    .navigationDestination(for: SendRoute.self) { route in
                        SendRouter().build(route)
                    }
                    .environmentObject(NavigationRouter())
                }
            }
        }
        .sheet(isPresented: $viewModel.showFastVaultPasswordPrompt) {
            if let tx = viewModel.pendingSendTx, let vault = appViewModel.selectedVault {
                FastVaultEnterPasswordView(
                    password: Binding(
                        get: { tx.fastVaultPassword },
                        set: { tx.fastVaultPassword = $0 }
                    ),
                    vault: vault,
                    onSubmit: {
                        viewModel.executeFastVaultKeysign(password: tx.fastVaultPassword, vault: vault)
                    }
                )
            }
        }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            Theme.colors.bgPrimary
            Image("agent-top-gradient")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            if hasActiveChat {
                Text(viewModel.conversationTitle ?? "Vulti Agent")
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            HStack {
                Button {
                    router.navigate(to: AgentRoute.conversations)
                } label: {
                    Image("alignment-left")
                        .foregroundStyle(Theme.colors.textPrimary)
                }

                Spacer()

                Menu {
                    if viewModel.conversationId != nil {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("agentDeleteConversation".localized, systemImage: "trash")
                        }
                    }
                    if isAuthorized {
                        Button {
                            disconnect()
                        } label: {
                            Label("agentDisconnect".localized, systemImage: "power")
                        }
                    }
                } label: {
                    Image("dot-grid-3-vertical")
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Hero Content (unauthorized + authorized empty)

    private var heroContent: some View {
        VStack(spacing: 0) {
            Spacer()
            orbImage
            titleSection
            Spacer()
        }
        .overlay(alignment: .bottom) {
            if isAuthorized {
                startersSection
            }
        }
    }

    private var orbImage: some View {
        Image("agent-orb")
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
    }

    private var titleSection: some View {
        VStack(spacing: 16) {
            Text(isAuthorized ? "agentWhatToDo".localized : "agentWelcomeTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(isAuthorized ? "agentWhatToDoSubtitle".localized : "agentWelcomeSubtitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: 295)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Starters

    private var startersSection: some View {
        FlowLayout(spacing: 8) {
            ForEach(viewModel.starters, id: \.self) { starter in
                starterPill(starter)
            }
        }
    }

    private func starterPill(_ text: String) -> some View {
        Button {
            inputText = text
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run { sendMessage() }
            }
        } label: {
            Text(text)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.colors.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        AgentChatMessageView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        AgentThinkingIndicator()
                            .id("thinking")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let lastId = viewModel.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    } else if viewModel.isLoading {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if isAuthorized {
            chatInputBar
        } else {
            unauthorizedBottomBar
        }
    }

    private var unauthorizedBottomBar: some View {
        AgentPasswordTextField(
            password: $password,
            errorMessage: authError,
            isAuthorizing: isAuthorizing,
            isFocused: $isPasswordFocused,
            onClear: { authError = nil },
            onSubmit: { authorize() }
        )
    }

    private var chatInputBar: some View {
        HStack(spacing: 12) {
            Button {
                router.navigate(to: AgentRoute.conversations)
            } label: {
                Image(systemName: "square.text.square")
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .frame(width: 40, height: 40)
            }

            TextField("agentStartTyping".localized, text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(20)
                .foregroundStyle(Theme.colors.textPrimary)
                .focused($isInputFocused)

            if viewModel.isLoading {
                Button {
                    viewModel.cancelRequest()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.alertError)
                }
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(Theme.fonts.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.colors.textTertiary
                                : Theme.colors.turquoise
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.colors.bgPrimary)
    }

    // MARK: - Actions

    private func checkAuth() {
        guard let vault = appViewModel.selectedVault else { return }
        viewModel.checkConnection(vault: vault)
        Task {
            await viewModel.loadStarters(vault: vault)
        }
    }

    private func authorize() {
        guard !password.isEmpty, let vault = appViewModel.selectedVault else { return }
        isAuthorizing = true
        authError = nil

        Task {
            let error = await viewModel.signIn(vault: vault, password: password)
            isAuthorizing = false
            if let error {
                authError = error
            } else {
                password = ""
                isPasswordFocused = false
                await viewModel.loadStarters(vault: vault)
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let vault = appViewModel.selectedVault else { return }
        inputText = ""
        isInputFocused = false
        viewModel.sendMessage(text, vault: vault)
    }

    private func loadConversation(id: String) {
        guard let vault = appViewModel.selectedVault else { return }
        // Reset current state for the new conversation
        viewModel.cancelRequest()
        viewModel.messages = []
        viewModel.conversationTitle = nil
        viewModel.conversationId = nil

        Task {
            await viewModel.loadConversation(id: id, vault: vault)
        }
    }

    private func deleteCurrentConversation() {
        guard let vault = appViewModel.selectedVault else { return }
        viewModel.deleteCurrentConversation(vault: vault)
    }

    private func disconnect() {
        guard let vault = appViewModel.selectedVault else { return }
        Task {
            await viewModel.disconnect(vault: vault)
            viewModel.messages = []
            viewModel.conversationTitle = nil
            viewModel.conversationId = nil
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let agentDidSelectConversation = Notification.Name("agentDidSelectConversation")
}

#Preview {
    AgentMainScreen()
        .environmentObject(AppViewModel())
}
