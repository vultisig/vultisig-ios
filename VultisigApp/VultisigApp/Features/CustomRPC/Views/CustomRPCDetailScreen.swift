//
//  CustomRPCDetailScreen.swift
//  VultisigApp
//

import SwiftUI

struct CustomRPCDetailScreen: View {
    @Environment(\.router) var router
    @StateObject private var viewModel: CustomRPCDetailViewModel

    init(chain: Chain) {
        _viewModel = StateObject(wrappedValue: CustomRPCDetailViewModel(chain: chain))
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 20) {
                header
                urlField
                testSection
                Spacer()
                actions
            }
        }
        .screenTitle(viewModel.chain.name)
        .onAppear {
            viewModel.load()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AsyncImageView(
                logo: viewModel.chain.logo,
                size: CGSize(width: 40, height: 40),
                ticker: viewModel.chain.ticker,
                tokenChainLogo: viewModel.chain.logo
            )
            Text(viewModel.chain.name)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            CustomRPCStatusChip(isCustom: viewModel.hasOverride)
        }
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommonTextField(
                text: $viewModel.urlText,
                label: "customRPCEndpointLabel".localized,
                placeholder: "https://"
            )

            if !viewModel.urlText.isEmpty && !viewModel.isURLValid {
                Text("customRPCInvalidURL".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertError)
            }
        }
    }

    @ViewBuilder
    private var testSection: some View {
        switch viewModel.probeState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                Text("customRPCTesting".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
        case .result(let result):
            probeResultView(result)
        }
    }

    @ViewBuilder
    private func probeResultView(_ result: RPCHealthResult) -> some View {
        switch result {
        case .ok(let latencyMs):
            label(
                String(format: "customRPCReachable".localized, latencyMs),
                color: Theme.colors.alertSuccess
            )
        case .unreachable:
            label("customRPCUnreachable".localized, color: Theme.colors.alertError)
        case .wrongChain(let expected, let got):
            label(
                String(format: "customRPCWrongChain".localized, expected, got),
                color: Theme.colors.alertError
            )
        case .invalidResponse:
            label("customRPCInvalidResponse".localized, color: Theme.colors.alertError)
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(color)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "customRPCTest".localized, type: .secondary) {
                Task { await viewModel.test() }
            }
            .disabled(!viewModel.isURLValid || viewModel.isProbing)

            PrimaryButton(title: "save".localized) {
                viewModel.save()
                router.navigateBack()
            }
            .disabled(!viewModel.canSave)

            if viewModel.canReset {
                PrimaryButton(title: "customRPCResetToDefault".localized, type: .secondary) {
                    viewModel.reset()
                }
            }
        }
    }
}
