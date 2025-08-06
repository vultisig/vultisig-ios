//
//  MacCheckUpToDateView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

struct UpdateCheckUpToDateView: View {
    let currentVersion: String
    
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            vultisigLogo
            upToDateTitle
            upToDateDescription
            Spacer()
        }
    }
    
    var vultisigLogo: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 60, height: 60)
    }
    
    var upToDateTitle: some View {
        Text(NSLocalizedString("appUpToDate", comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(.top, 24)
    }
    
    var upToDateDescription: some View {
        Text(currentVersion)
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }
}

#Preview {
    UpdateCheckUpToDateView(currentVersion: "v1.0.1")
}
