//
//  ReferralOnboardingGuideAnimation+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-04.
//

#if os(iOS)
import SwiftUI

extension ReferralOnboardingGuideAnimation {
    func getCell(
        icon: String,
        title: String,
        description: String,
        showCell: Bool
    ) -> some View {
        HStack(spacing: 0){
            Rectangle()
                .frame(width: 22, height: 2)
                .foregroundColor(.blue600)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.persianBlue200)
                    .font(.body20MontserratMedium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(title, comment: ""))
                        .font(.body14BrockmannMedium)
                    
                    Text(NSLocalizedString(description, comment: ""))
                        .font(.body10BrockmannMedium)
                }
                .foregroundColor(.neutral0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue200, lineWidth: 1)
            )
        }
        .opacity(showCell ? 1 : 0)
        .offset(y: showCell ? 0 : -10)
        .animation(.easeInOut, value: showCell)
    }
}
#endif
