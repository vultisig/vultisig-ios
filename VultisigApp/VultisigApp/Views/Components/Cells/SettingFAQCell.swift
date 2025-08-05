//
//  SettingFAQCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingFAQCell: View {
    
    let question: String
    let answer: String
    
    @State var isExpanded = false
    
    var body: some View {
        container
            .background(Theme.colors.bgSecondary)
            .cornerRadius(10)
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            questionBlock
            
            if isExpanded {
                Separator()
                description
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
    
    var questionBlock: some View {
        HStack(spacing: 12) {
            title
            Spacer()
            chevron
        }
    }
    
    var title: some View {
        Text(NSLocalizedString(question, comment: "Question"))
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var description: some View {
        Text(NSLocalizedString(answer, comment: "Answer"))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textLight)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.down")
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }
}

#Preview {
    SettingFAQCell(question: "vaultSecurityFAQQuestion", answer: "setupVaultFAQQuestion")
}
