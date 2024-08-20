//
//  KeyGenSummaryView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct KeyGenSummaryView: View {
    @ObservedObject var viewModel: KeygenPeerDiscoveryViewModel
    
    @State var numberOfMainDevices = 0
    @State var numberOfBackupDevices = 0
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationTitle(NSLocalizedString("keygen", comment: "Keygen"))
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
            VStack(spacing: 32) {
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
        VStack(spacing: 12) {
            title
            numberOfDevicesTitle
        }
    }
    
    var devicesList: some View {
        VStack(spacing: 16) {
            devicesListTitle
            list
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("youAreCreatingA", comment: "You are creating a"))
            .font(.body12MontserratSemiBold)
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
    
    var devicesListTitle: some View {
        Text(NSLocalizedString("withTheseDevices", comment: "With these devices"))
            .font(.body12MontserratSemiBold)
    }
    
    var list: some View {
        var index = 0
        var pairDevices = numberOfMainDevices
        
        return VStack(spacing: 16) {
            ForEach(Array(viewModel.selections), id: \.self) { selection in
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
    
    var buttons: some View {
        VStack(spacing: 16) {
            disclaimers
            button
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 26)
    }
    
    var button: some View {
        Button {
            viewModel.startKeygen()
        } label: {
            FilledButton(title: "continue")
        }
    }
    
    private func getCell(index: Int, title: String, isPairDevice: Bool) -> some View {
        Group {
            Text(String(describing: index)) +
            Text(". ") +
            Text(title) +
            Text(" (") +
            Text(getDeviceState(deviceId: title, isPairDevice: isPairDevice)) +
            Text(")")
        }
        .font(.body12Menlo)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    private func getOutlinedCell(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(LinearGradient.primaryGradient)
                .font(.body14Menlo)
            
            Text(text)
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
            #if os(iOS)
                .stroke(LinearGradient.primaryGradient, lineWidth: 1)
            #elseif os(macOS)
                .stroke(LinearGradient.primaryGradient, lineWidth: 2)
            #endif
        )
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
}

#Preview {
    KeyGenSummaryView(viewModel: KeygenPeerDiscoveryViewModel())
}
