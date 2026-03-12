//
//  AgentChatView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentChatView: View {
    let conversationId: String?

    @EnvironmentObject private var appViewModel: AppViewModel
    @StateObject private var viewModel = AgentChatViewModel()
    @State private var inputText = ""
    @State private var showPasswordPrompt = false
    @State private var showDeleteConfirm = false
    @State private var showFeedback = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.router) private var router

    var body: some View {
        VStack(spacing: 0) {
            inlineHeader
            Separator(color: Theme.colors.borderLight, opacity: 1)
            VStack(spacing: 0) {
                messagesList
                inputBar
            }
        }
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(
            "agentDeleteConversationTitle".localized,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("delete".localized, role: .destructive) {
                guard let vault = appViewModel.selectedVault else { return }
                viewModel.deleteCurrentConversation(vault: vault)
            }
            Button("cancel".localized, role: .cancel) {}
        } message: {
            Text("agentDeleteConversationMessage".localized)
        }
        .onChange(of: viewModel.conversationDeleted) { _, deleted in
            if deleted {
                router.navigateBack()
            }
        }
        .onAppear {
            setupChat()
        }
        .onChange(of: viewModel.passwordRequired) { _, required in
            showPasswordPrompt = required
        }
        .sheet(isPresented: $showPasswordPrompt) {
            if let vault = appViewModel.selectedVault {
                AgentPasswordPromptScreen(usesFastVault: true) { password in
                    await viewModel.signIn(vault: vault, password: password)
                }
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
        .alert("error".localized, isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("ok".localized) { viewModel.dismissError() }
        } message: {
            Text(viewModel.error ?? "")
        }
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
                AgentApproveTransactionView(
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
        .onReceive(NotificationCenter.default.publisher(for: .agentDidBroadcastTx)) { notif in
            if let txid = notif.userInfo?["txid"] as? String, let vault = appViewModel.selectedVault {
                viewModel.handleTxBroadcasted(txid: txid, vault: vault)
            }
        }
        .sheet(isPresented: $showFeedback) {
            AgentFeedbackView(
                conversationId: viewModel.conversationId
            ) { category, details in
                guard let vault = appViewModel.selectedVault else { return }
                await viewModel.submitFeedback(category: category, details: details, vault: vault)
            }
        }
    }

    // MARK: - Inline Header

    private var inlineHeader: some View {
        ZStack {
            Text(viewModel.conversationTitle ?? "Vultisig")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)

            HStack {
                Button {
                    router.navigateBack()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }

                Spacer()

                if conversationId != nil || viewModel.conversationId != nil {
                    Menu {
                        Button {
                            showFeedback = true
                        } label: {
                            Label("agentGiveFeedback".localized, systemImage: "info.circle")
                        }

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("agentDeleteChatSession".localized, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgPrimary)
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        startersView
                    }

                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        // Date separator when day changes
                        if index == 0 || !Calendar.current.isDate(message.timestamp, inSameDayAs: viewModel.messages[index - 1].timestamp) {
                            dateSeparator(for: message.timestamp)
                        }

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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("agentMessagePlaceholder".localized, text: $inputText, axis: .vertical)
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

    private func setupChat() {
        guard let vault = appViewModel.selectedVault else { return }
        viewModel.checkConnection(vault: vault)

        if let convId = conversationId {
            Task {
                await viewModel.loadConversation(id: convId, vault: vault)
            }
        } else {
            Task {
                await viewModel.loadStarters(vault: vault)
            }
        }

        // Check for pending starter message
        if let starter = UserDefaults.standard.string(forKey: "agent_pending_starter") {
            UserDefaults.standard.removeObject(forKey: "agent_pending_starter")
            inputText = starter
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run { sendMessage() }
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

    // MARK: - Date Separator

    private func dateSeparator(for date: Date) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Theme.colors.borderLight)
                .frame(height: 1)
            Text(Self.dateSeparatorFormatter.string(from: date))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .layoutPriority(1)
            Rectangle()
                .fill(Theme.colors.borderLight)
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }

    private static let dateSeparatorFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, yyyy"
        return f
    }()

    // MARK: - Starters UI

    private var startersView: some View {
        VStack(spacing: 16) {
            Spacer()

            AgentOrbView(size: 64, animated: true)

            Text("agentWhatWouldYouDo".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("agentStarterSubtitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Horizontal scrolling pill chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.starters, id: \.self) { starter in
                        starterChip(starter)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func starterChip(_ text: String) -> some View {
        Button {
            inputText = text
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run { sendMessage() }
            }
        } label: {
            Text(text)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
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
}

#Preview {
    NavigationStack {
        AgentChatView(conversationId: nil)
            .environmentObject(AppViewModel())
    }
}

extension Notification.Name {
    static let agentDidAcceptTx = Notification.Name("agentDidAcceptTx")
    static let agentDidRejectTx = Notification.Name("agentDidRejectTx")
    static let agentDidBroadcastTx = Notification.Name("agentDidBroadcastTx")
}
