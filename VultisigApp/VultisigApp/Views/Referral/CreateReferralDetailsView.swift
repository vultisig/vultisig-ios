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
    @ObservedObject var functionCallViewModel: FunctionCallViewModel
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State var showTooltip = false
    
    var body: some View {
        container
            .onAppear {
                setData()
            }
            .alert(isPresented: $referralViewModel.showReferralAlert) {
                alert
            }
            .onChange(of: referralViewModel.expireInCount) { oldValue, newValue in
                calculateFees()
            }
    }
    
    var content: some View {
        ZStack {
            Background()
            
            VStack {
                tooltip
                main
                button
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
                choosePayoutAsset
                separator
                summary
            }
            .padding(24)
        }
    }
    
    var pickReferralCode: some View {
        PickReferralCode(referralViewModel: referralViewModel)
    }
    
    var setExpiration: some View {
        VStack(spacing: 8) {
            setExpirationTitle
            setExpirationCounter
            expirationDate
        }
    }
    
    var setExpirationTitle: some View {
        Text(NSLocalizedString("setExpiration(inYears)", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var setExpirationCounter: some View {
        HStack {
            decreaseExpirationButton
            expiratingInCounter
            increaseExpirationButton
        }
    }
    
    var expirationDate: some View {
        getCell(
            title: "expirationDate",
            description1: getExpirationDate(),
            description2: "",
            isPlaceholder: referralViewModel.expireInCount == 0
        )
    }
    
    var decreaseExpirationButton: some View {
        Button {
            referralViewModel.handleCounterDecrease()
        } label: {
            getExpirationCounterButton(icon: "minus.circle")
        }
        .disabled(referralViewModel.expireInCount == 0)
        .opacity(referralViewModel.expireInCount == 0 ? 0.2 : 1)
    }
    
    var expiratingInCounter: some View {
        getExpirationCounterButton(value: "\(referralViewModel.expireInCount)")
    }
    
    var increaseExpirationButton: some View {
        Button {
            referralViewModel.handleCounterIncrease()
        } label: {
            getExpirationCounterButton(icon: "plus.circle")
        }
    }
    
    var choosePayoutAsset: some View {
        VStack(spacing: 8) {
            choosePayoutAssetTitle
            choosePayoutAssetSelection
        }
    }
    
    var choosePayoutAssetTitle: some View {
        Text(NSLocalizedString("choosePayoutAsset", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var choosePayoutAssetSelection: some View {
        HStack {
            selectedAsset
            Spacer()
        }
        .frame(height: 56)
        .font(.body16BrockmannMedium)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .padding(1)
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
                title: NSLocalizedString("totalFee", comment: ""),
                description1: "\(referralViewModel.getTotalFee()) RUNE",
                description2: "\(referralViewModel.totalFeeFiat)",
                isPlaceholder: referralViewModel.isTotalFeesLoading
            )
        }
    }
    
    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.02, green: 0.11, blue: 0.23), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.16, green: 0.27, blue: 0.44), location: 0.49),
                        Gradient.Stop(color: Color(red: 0.02, green: 0.11, blue: 0.23), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            )
    }
    
    var button: some View {
        Button {
            referralViewModel.verifyReferralEntries(tx: sendTx, functionCallViewModel: functionCallViewModel)
        } label: {
            label
        }
        .padding(24)
    }
    
    var label: some View {
        FilledButton(title: "createReferral", textColor: .neutral0, background: .persianBlue400)
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
            
            Text("RUNE")
                .font(.body16BrockmannMedium)
                .foregroundColor(.neutral0)
        }
    }
    
    var infoLabel: some View {
        Image(systemName: "info.circle")
            .font(.body18MenloBold)
            .foregroundColor(.neutral0)
    }
    
    var tooltip: some View {
        VStack(alignment: .leading) {
            Text(NSLocalizedString("referralProgram", comment: ""))
                .foregroundColor(.neutral900)
                .font(.body16BrockmannMedium)
            
             Text(NSLocalizedString("referralProgramTooltipDescription", comment: ""))
                .foregroundColor(.extraLightGray)
                    .font(.body14BrockmannMedium)
        }
        .animation(.easeInOut, value: showTooltip)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.neutral0)
        .cornerRadius(8)
        .padding(.horizontal, 24)
        .onTapGesture {
            showTooltip = false
        }
        .frame(maxHeight: showTooltip ? nil : 0)
        .clipped()
    }
    
    private func getExpirationCounterButton(icon: String? = nil, value: String? = nil) -> some View {
        ZStack {
            if let icon {
                Image(systemName: icon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue600)
                    .font(.body22BrockmannMedium)
            } else if let value {
                Text(value)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.clear)
                    .font(.body16BrockmannMedium)
            }
        }
        .foregroundColor(.neutral0)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue400, lineWidth: 1)
        )
    }
    
    private func getCell(title: String, description1: String, description2: String, isPlaceholder: Bool) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 0) {
                Text(description1)
                    .foregroundColor(.neutral0)
                
                if !description2.isEmpty {
                    Text(description2)
                        .foregroundColor(.extraLightGray)
                }
            }
            .redacted(reason: isPlaceholder ? .placeholder : [])
        }
        .font(.body14BrockmannMedium)
    }
    
    private func setData() {
        referralViewModel.getNativeCoin(tx: sendTx)
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
    CreateReferralDetailsView(sendTx: SendTransaction(), referralViewModel: ReferralViewModel(), functionCallViewModel: FunctionCallViewModel())
}
