//
//  KeyGenSummaryView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct KeyGenSummaryView: View {
    let state: SetupVaultState
    let tssType: TssType

    @ObservedObject var viewModel: KeygenPeerDiscoveryViewModel

    @State var numberOfMainDevices = 0
    @State var numberOfBackupDevices = 0
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationTitle(NSLocalizedString(getTitle(), comment: ""))
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        VStack {
            content
            buttons
        }
    }
    
    var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                devicesList
            }
            .padding(.top, 30)
            .padding(.horizontal, 22)
            .foregroundColor(.neutral0)
            .scrollIndicators(.hidden)
        }
    }
    
    var header: some View {
        ZStack {
            if tssType == .Reshare {
                numberOfDevicesForReshareTitle
            } else {
                numberOfDevicesTitle
            }
        }
    }
    
    var devicesList: some View {
        VStack(spacing: 16) {
            if tssType == .Keygen {
                devicesListTitle
            }
            
            list
        }
    }
    
    var numberOfDevicesTitle: some View {
        Group {
            Text("\(numberOfMainDevices) ") +
            Text(NSLocalizedString("of", comment: "of")) +
            Text(" \(numberOfMainDevices+numberOfBackupDevices) ") +
            Text(NSLocalizedString("vault", comment: "vault"))
        }
        .font(.body20MontserratSemiBold)
    }
    
    var numberOfDevicesForReshareTitle: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("newVaultSetup", comment: ""))
                .font(.body14MenloBold)
            
            Group {
                Text("\(numberOfMainDevices) ") +
                Text(NSLocalizedString("of", comment: "of")) +
                Text(" \(numberOfMainDevices) ")
            }
            .font(.body14MontserratSemiBold)
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
            .background(Color.blue400)
            .cornerRadius(4)
        }
    }
    
    var devicesListTitle: some View {
        Text(NSLocalizedString("withTheseDevices", comment: "With these devices"))
            .font(.body12MontserratSemiBold)
            .padding(.bottom, 20)
    }
    
    var list: some View {
        var index = 0
        var pairDevices = numberOfMainDevices
        
        return VStack(spacing: 16) {
            ForEach(viewModel.selections.map{ $0 }, id: \.self) { selection in
                index += 1
                pairDevices -= selection==viewModel.localPartyID ? 0 : 1
                return getCell(index: index, title: selection, isPairDevice: pairDevices>0)
            }
        }
    }
    
    var disclaimers: some View {
        VStack(alignment: .leading, spacing: 16) {
            pairDeviceDisclaimers
            backupDeviceDisclaimers
        }
        .foregroundColor(.neutral0)
        .font(.body12Menlo)
        .multilineTextAlignment(.leading)
    }
    
    var pairDeviceDisclaimers: some View {
        let text = NSLocalizedString("pairDeviceDisclaimersFirst", comment: "") + " " + getCountInWords() + " "  + NSLocalizedString("pairDeviceDisclaimersSecond", comment: "")
        
        return getOutlinedCell(text)
    }
    
    var backupDeviceDisclaimers: some View {
        getOutlinedCell(NSLocalizedString("shouldBackupVaultsSeparateLocations", comment: ""))
    }
    
    var reshareDisclaimer: some View {
        getOutlinedCell(NSLocalizedString("yourConfigurationChangedMakeBackup", comment: ""))
    }
    
    var buttons: some View {
        VStack(spacing: 16) {
            if tssType == .Keygen {
                disclaimers
            } else {
                reshareDisclaimer
            }
            
            button
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 26)
    }
    
    var button: some View {
        Button {
            viewModel.startKeygen()
        } label: {
            FilledButton(title: tssType == .Keygen ? "continue" : "start")
        }
        .disabled(!isButtonEnabled)
        .opacity(isButtonEnabled ? 1.0 : 0.5)
    }

    var isButtonEnabled: Bool {
        return viewModel.isValidPeers(state: state)
    }

    private func getCell(index: Int, title: String, isPairDevice: Bool) -> some View {
        let deviceState = getDeviceState(deviceId: title, isPairDevice: isPairDevice)
        
        return Group {
            Text(String(describing: index)) +
            Text(". ") +
            Text(title) +
            Text(" (") +
            Text(deviceState) +
            Text(")")
        }
        .font(.body12Menlo)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(getCellBackground(deviceState))
        .cornerRadius(10)
    }
    
    private func getOutlinedCell(_ text: String) -> some View {
        OutlinedDisclaimer(text: text)
    }
    
    private func setData() {
        let numberOfDevices = viewModel.selections.count
        let doubleValue = (2*Double(numberOfDevices))/3
        numberOfMainDevices = Int(ceil(doubleValue))
        numberOfBackupDevices = numberOfDevices-numberOfMainDevices
    }
    
    private func getCountInWords() -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .spellOut
        return numberFormatter.string(from: NSNumber(value: numberOfMainDevices))?.capitalized ?? "Two"
    }
    
    private func getDeviceState(deviceId: String, isPairDevice: Bool) -> String {
        let deviceState: String
        
        if deviceId == viewModel.localPartyID {
            deviceState = "thisDevice"
        } else if isPairDevice {
            deviceState = "pairDevice"
        } else {
            deviceState = "backupDevice"
        }
        return NSLocalizedString(deviceState, comment: "")
    }
    
    private func getTitle() -> String {
        if tssType == .Reshare {
            return "changesInSetup"
        } else {
            return "keygen"
        }
    }
    
    private func getCellBackground(_ deviceState: String) -> Color {
        guard tssType == .Reshare else {
            return Color.blue600
        }
        
        if deviceState == "Backup Device" {
            return Color.reshareCellRed.opacity(0.5)
        } else {
            return Color.reshareCellGreen.opacity(0.35)
        }
    }
}

#Preview {
    KeyGenSummaryView(state: .fast, tssType: .Reshare, viewModel: KeygenPeerDiscoveryViewModel())
}
