//
//  CreateReferralDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-18.
//

import SwiftUI

struct CreateReferralDetailsView: View {
    @ObservedObject var sendTx: SendTransaction
    @ObservedObject var referralViewModel: ReferralViewModel
    var onNext: () -> Void

    @EnvironmentObject var homeViewModel: HomeViewModel

    @State var showTooltip = false

    var body: some View {
        Screen(showNavigationBar: false) {
            VStack {
                if showTooltip {
                    tooltip
                }
                main
                button
            }
        }
        .onLoad {
            setData()
        }
        .alert(isPresented: $referralViewModel.showReferralAlert) {
            alert
        }
        .onChange(of: referralViewModel.expireInCount) { _, _ in
            calculateFees()
        }
        .crossPlatformToolbar("createReferral".localized) {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "circle-info") {
                    showTooltip.toggle()
                }
            }
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
        PickReferralCode(referralViewModel: referralViewModel)
    }

    var setExpiration: some View {
        VStack(spacing: 8) {
            setExpirationTitle
            CounterView(count: $referralViewModel.expireInCount, minimumValue: 1)
            expirationDate
        }
    }

    var setExpirationTitle: some View {
        Text(NSLocalizedString("setExpiration(inYears)", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var expirationDate: some View {
        getCell(
            title: "expirationDate",
            description1: getExpirationDate(),
            description2: "",
            isPlaceholder: referralViewModel.expireInCount == 0
        )
    }

    var summary: some View {
        VStack(spacing: 16) {
            getCell(
                title: NSLocalizedString("registrationFee", comment: ""),
                description1: "\(referralViewModel.getRegistrationFee()) RUNE",
                description2: "\(referralViewModel.registrationFeeFiat)",
                isPlaceholder: referralViewModel.isFeesLoading
            )

            getCell(
                title: NSLocalizedString("costs", comment: ""),
                description1: "\(referralViewModel.getTotalFee()) RUNE",
                description2: "\(referralViewModel.totalFeeFiat)",
                isPlaceholder: referralViewModel.isTotalFeesLoading
            )
        }
    }

    var separator: some View {
        LinearSeparator()
    }

    var button: some View {
        PrimaryButton(title: "createReferralCode") {
            Task {
                guard await referralViewModel.verifyReferralEntries(tx: sendTx) else {
                    return
                }

                onNext()
            }
        }
        .disabled(!referralViewModel.createReferralButtonEnabled)
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(referralViewModel.referralAlertMessage, comment: "")),
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
                .foregroundColor(Theme.colors.textPrimary)
        }
    }

    var infoLabel: some View {
        Image(systemName: "info.circle")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var tooltip: some View {
        VStack(alignment: .leading) {
            Text(NSLocalizedString("referralProgram", comment: ""))
                .foregroundColor(Theme.colors.textDark)
                .font(Theme.fonts.bodyMMedium)

             Text(NSLocalizedString("referralProgramTooltipDescription", comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
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
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(description1)
                    .foregroundColor(Theme.colors.textPrimary)

                if !description2.isEmpty {
                    Text(description2)
                        .foregroundColor(Theme.colors.textTertiary)
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
            await referralViewModel.loadGasInfoForSending(tx: sendTx)
        }
    }

    private func calculateFees() {
        Task {
            await referralViewModel.calculateFees()
        }
    }

    private func getExpirationDate() -> String {
        let currentDate = Date()
        let oneYearLater = Calendar.current.date(byAdding: .year, value: referralViewModel.expireInCount, to: currentDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")

        let formattedDate = formatter.string(from: oneYearLater ?? Date())
        return formattedDate
    }
}

#Preview {
    CreateReferralDetailsView(
        sendTx: SendTransaction(),
        referralViewModel: ReferralViewModel(),
        onNext: {}
    )
}
