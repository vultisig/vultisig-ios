//
//  KeyGenSummaryView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct KeyGenSummaryView: View {
    let numberOfDevices: Int
    
    @State var numberOfMainDevices = 0
    @State var numberOfBackupDevices = 0
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationTitle(NSLocalizedString("summary", comment: "Summary"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        VStack {
            content
            button
        }
    }
    
    var content: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                devicesList
                disclaimers
            }
            .padding(.top, 30)
            .padding(.horizontal, 22)
            .foregroundColor(.neutral0)
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
            Text(NSLocalizedString("vaults", comment: "vaults"))
        }
        .font(.body20MontserratSemiBold)
    }
    
    var devicesListTitle: some View {
        Text(NSLocalizedString("withTheseDevices", comment: "With these devices"))
            .font(.body12MontserratSemiBold)
    }
    
    var list: some View {
        VStack {
            
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
        Group {
            Text(NSLocalizedString("pairDeviceDisclaimersFirst", comment: "")) +
            Text(" ") +
            Text(getCountInWords()).bold() +
            Text(" ") +
            Text(NSLocalizedString("pairDeviceDisclaimersSecond", comment: ""))
        }
    }
    
    var backupDeviceDisclaimers: some View {
        ZStack {
            if numberOfDevices > 2 {
                Text(NSLocalizedString("backupNotNeededDisclaimer", comment: ""))
            } else {
                Text(NSLocalizedString("noBackupDeviceDisclaimer", comment: ""))
            }
        }
    }
    
    var button: some View {
        FilledButton(title: "continue")
            .padding(40)
    }
    
    private func setData() {
        guard numberOfDevices>2 else {
            numberOfMainDevices = numberOfDevices
            numberOfBackupDevices = 0
            return
        }
        
        let doubleValue = (2*Double(numberOfDevices))/3
        numberOfMainDevices = Int(ceil(doubleValue))
        numberOfBackupDevices = numberOfDevices-numberOfMainDevices
    }
    
    private func getCountInWords() -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .spellOut
        return numberFormatter.string(from: NSNumber(value: numberOfMainDevices))?.capitalized ?? "Two"
    }
}

#Preview {
    KeyGenSummaryView(numberOfDevices: 20)
}
