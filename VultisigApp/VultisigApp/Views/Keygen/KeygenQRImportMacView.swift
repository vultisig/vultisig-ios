//
//  KeygenQRImportMacView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI

struct KeygenQRImportMacView: View {
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationTitle("pair")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
    }
    
    var content: some View {
        VStack(spacing: 32) {
            title
            uploadSection
            Spacer()
            button
        }
        .padding(40)
    }
    
    var title: some View {
        Text(NSLocalizedString("uploadQRCodeImageKeygen", comment: ""))
            .font(.body16MontserratBold)
            .foregroundColor(.neutral0)
    }
    
    var uploadSection: some View {
        FileQRCodeImporterMac()
    }
    
    var button: some View {
        FilledButton(title: "continue")
    }
}

#Preview {
    KeygenQRImportMacView()
}
