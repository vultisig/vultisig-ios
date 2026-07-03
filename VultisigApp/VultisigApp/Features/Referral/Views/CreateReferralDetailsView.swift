//
//  CreateReferralDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-18.
//

import SwiftUI

struct CreateReferralDetailsView: View {
    @Bindable var viewModel: ReferralDetailsViewModel
    var onNext: (SendTransaction) -> Void

    @EnvironmentObject var homeViewModel: HomeViewModel

    @State var showTooltip = false

    var body: some View {
        Screen {
            VStack {
                if showTooltip {
                    tooltip
                }
                main
                button
            }
        }
        .screenTitle("createReferral".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "circle-info") {
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
            VStack(spacing: 16) {
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
        }
    }

    var setExpirationTitle: some View {
        Text(NSLocalizedString("setExpiration(inYears)", comment: ""))
            .foregroundStyle(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var expirationDate: some View {
        getCell(
            title: "expirationDate",
            description1: getExpirationDate(),
            description2: "",
            isPlaceholder: viewModel.expireInCount == 0
        )
    }

    var summary: some View {
        VStack(spacing: 16) {
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
        LinearSeparator()
    }

    var button: some View {
        PrimaryButton(title: "createReferralCode") {
            Task {
                guard let tx = await viewModel.verifyReferralEntries() else {
                    return
                }

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
            Image("rune")
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
        VStack(alignment: .leading) {
            Text(NSLocalizedString("referralProgram", comment: ""))
                .foregroundStyle(Theme.colors.textDark)
                .font(Theme.fonts.bodyMMedium)

             Text(NSLocalizedString("referralProgramTooltipDescription", comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Theme.colors.textPrimary)
        .cornerRadius(8)
        .onTapGesture {
            showTooltip = false
        }
    }

    private func getCell(title: String, description1: String, description2: String, isPlaceholder: Bool) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(description1)
                    .foregroundStyle(Theme.colors.textPrimary)

                if !description2.isEmpty {
                    Text(description2)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .redacted(reason: isPlaceholder ? .placeholder : [])
        }
        .font(Theme.fonts.bodySMedium)
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
