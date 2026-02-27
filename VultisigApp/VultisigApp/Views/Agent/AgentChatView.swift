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
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                messagesList
                inputBar
            }
        }
        .navigationTitle(viewModel.conversationTitle ?? "Vulti")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            setupChat()
        }
        .onChange(of: viewModel.passwordRequired) { _, required in
            showPasswordPrompt = required
        }
        .sheet(isPresented: $showPasswordPrompt) {
            AgentPasswordPromptView { password in
                guard let vault = appViewModel.selectedVault else { return }
                Task {
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
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        startersView
                    }
                    
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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message Vulti...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(20)
                .foregroundColor(Theme.colors.textPrimary)
                .focused($isInputFocused)

            if viewModel.isLoading {
                Button {
                    viewModel.cancelRequest()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.colors.alertError)
                }
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                sendMessage()
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
    
    // MARK: - Starters UI
    
    private var startersView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.colors.turquoise, Theme.colors.primaryAccent3],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Ask Vulti Anything")
                .font(.title2.bold())
                .foregroundColor(Theme.colors.textPrimary)

            Text("Try one of these suggestions below or type your own question.")
                .font(.subheadline)
                .foregroundColor(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Starter suggestions
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(viewModel.starters, id: \.self) { starter in
                    starterCard(starter)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func starterCard(_ text: String) -> some View {
        Button {
            inputText = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                sendMessage()
            }
        } label: {
            HStack {
                Text(text)
                    .font(.footnote)
                    .foregroundColor(Theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
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
}
