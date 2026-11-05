//
//  CreateReferralDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-18.
//

import SwiftUI
import VultisigUIResources

struct CreateReferralDetailsView: View {
    @Bindable var viewModel: ReferralDetailsViewModel
    var onNext: (SendTransaction) -> Void

    @EnvironmentObject var homeViewModel: HomeViewModel

    @State var showTooltip = false

    private let tooltipWidth: CGFloat = 300
    private let tooltipArrowFraction: CGFloat = 0.94

    var body: some View {
        Screen {
            VStack {
                main
                button
            }
            .overlay(alignment: .topTrailing) {
                if showTooltip {
                    tooltip
                }
            }
        }
        .screenTitle("createReferral".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: .circleInfo) {
                    showTooltip.toggle()
                }
            }
        }
        .onLoad {
            setData()
        }
        .alert(isPresented: $viewModel.showReferralAlert) {
            alert
        }
        .onChange(of: viewModel.expireInCount) { _, _ in
            calculateFees()
        }
    }

    var main: some View {
        ScrollView {
            VStack(spacing: 14) {
                pickReferralCode
                separator
                setExpiration
                separator
                summary
            }
        }
    }

    var pickReferralCode: some View {
        PickReferralCode(viewModel: viewModel)
    }

    var setExpiration: some View {
        VStack(spacing: 8) {
            setExpirationTitle
            CounterView(count: $viewModel.expireInCount, minimumValue: 1)
            expirationDate
                .padding(.top, 6)
        }
    }

    var setExpirationTitle: some View {
        Text(NSLocalizedString("setExpiration(inYears)", comment: ""))
            .foregroundStyle(Theme.colors.textPrimary)
            .settingsText(.bodyS)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var expirationDate: some View {
        getCell(
            title: "expirationDate",
            description1: getExpirationDate(),
            description2: "",
            titleStyle: .bodyS,
            isPlaceholder: viewModel.expireInCount == 0
        )
    }

    var summary: some View {
        VStack(spacing: 14) {
            getCell(
                title: NSLocalizedString("registrationFee", comment: ""),
                description1: "\(viewModel.getRegistrationFee()) RUNE",
                description2: "\(viewModel.registrationFeeFiat)",
                isPlaceholder: viewModel.isFeesLoading
            )

            getCell(
                title: NSLocalizedString("costs", comment: ""),
                description1: "\(viewModel.getTotalFee()) RUNE",
                description2: "\(viewModel.totalFeeFiat)",
                isPlaceholder: viewModel.isTotalFeesLoading
            )
        }
    }

    var separator: some View {
        Separator(color: Theme.colors.borderLight, opacity: 1)
            .padding(.vertical, -0.5) // Takes the line out of the 14pt rhythm, as in the design.
    }

    var button: some View {
        PrimaryButton(title: "createReferralCode", size: .compactSemibold) {
            Task {
                guard let tx = await viewModel.verifyReferralEntries() else {
                    return
                }

                // The referral field owns no focus state, so the responder is
                // resigned directly — Verify is a push, and it would otherwise
                // arrive over a live keyboard.
                hideKeyboard()
                onNext(tx)
            }
        }
        .disabled(!viewModel.createReferralButtonEnabled)
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(viewModel.referralAlertMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var selectedAsset: some View {
        HStack(spacing: 8) {
            VultisigImage("rune")
                .resizable()
                .frame(width: 32, height: 32)

            Text("rune".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var infoLabel: some View {
        Image(systemName: "info.circle")
            .font(Theme.fonts.bodyLMedium)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    var tooltip: some View {
        InfoTooltip(
            title: "referralProgram".localized,
            description: "referralProgramTooltipDescription".localized,
            arrowXFraction: tooltipArrowFraction,
            maxWidth: tooltipWidth
        ) {
            showTooltip = false
        }
        .frame(width: tooltipWidth)
        .padding(.trailing, 4)
        .offset(y: -13)
        .onTapGesture {
            showTooltip = false
        }
    }

    private func getCell(
        title: String,
        description1: String,
        description2: String,
        titleStyle: SettingsTextStyle = .footnote,
        isPlaceholder: Bool
    ) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
                .settingsText(titleStyle)
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(description1)
                    .settingsText(.bodyS)
                    .foregroundStyle(Theme.colors.textPrimary)

                if !description2.isEmpty {
                    Text(description2)
                        .settingsText(.bodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .redacted(reason: isPlaceholder ? .placeholder : [])
        }
    }

    private func setData() {
        loadGas()
        calculateFees()
    }

    private func loadGas() {
        Task {
            await viewModel.loadGasInfo()
        }
    }

    private func calculateFees() {
        Task {
            await viewModel.calculateFees()
        }
    }

    private func getExpirationDate() -> String {
        let currentDate = Date()
        let oneYearLater = Calendar.current.date(byAdding: .year, value: viewModel.expireInCount, to: currentDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")

        let formattedDate = formatter.string(from: oneYearLater ?? Date())
        return formattedDate
    }
}
