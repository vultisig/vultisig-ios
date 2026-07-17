//
//  CustomRPCDetailScreen.swift
//  VultisigApp
//

import SwiftUI

/// Per-chain custom RPC editor. New state (no override) shows the endpoint
/// field and Save RPC. Edit state (override set) adds a read-only default
/// endpoint card and Reset to Default. Save probes the endpoint first and only
/// persists when it is reachable on the right chain.
struct CustomRPCDetailScreen: View {
    @Environment(\.router) var router
    @StateObject private var viewModel: CustomRPCDetailViewModel
    @FocusState private var fieldFocused: Bool
    @State private var bannerText: String?

    init(chain: Chain) {
        _viewModel = StateObject(wrappedValue: CustomRPCDetailViewModel(chain: chain))
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                endpointField
                if viewModel.hasOverride {
                    defaultEndpointCard
                }
                Spacer()
                actions
            }
        }
        .screenTitle(viewModel.screenTitle)
        .onAppear {
            viewModel.load()
        }
        .withBanner(text: $bannerText)
    }

    private var endpointField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("customRPCEndpointSectionTitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            HStack(alignment: .top, spacing: 4) {
                TextField("", text: $viewModel.urlText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .focused($fieldFocused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Button(action: paste) {
                    Icon(.copy2, color: Theme.colors.textPrimary, size: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("paste".localized)
            }
            .padding(16)
            .frame(minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )

            if let saveError = viewModel.saveError {
                Text(saveError)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.alertError)
            } else {
                Text("customRPCEndpointHelper".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
        }
    }

    private var defaultEndpointCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("customRPCDefaultEndpointSectionTitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(viewModel.defaultEndpoint ?? "")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    private var actions: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "customRPCSaveButton".localized, isLoading: viewModel.isSaving) {
                Task {
                    if await viewModel.save() {
                        bannerText = String(
                            format: "customRPCModifiedSuccess".localized,
                            viewModel.chain.name
                        )
                        try? await Task.sleep(for: .seconds(1.2))
                        router.navigateBack()
                    }
                }
            }
            .disabled(!viewModel.canSave)

            if viewModel.hasOverride {
                PrimaryButton(title: "customRPCResetToDefault".localized, type: .secondary) {
                    viewModel.reset()
                }
                .disabled(!viewModel.canReset)
            }
        }
    }

    private func paste() {
        guard let pasted = ClipboardManager.pasteFromClipboard() else { return }
        viewModel.urlText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
