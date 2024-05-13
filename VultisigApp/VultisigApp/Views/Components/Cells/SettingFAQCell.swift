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
        VStack(alignment: .leading, spacing: 12) {
            questionBlock
            
            if isExpanded {
                Separator()
                description
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
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
            .font(.body14Menlo)
            .foregroundColor(.neutral0)
    }
    
    var description: some View {
        Text(NSLocalizedString(answer, comment: "Answer"))
            .font(.body12Menlo)
            .foregroundColor(.neutral300)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.body14Menlo)
            .foregroundColor(.neutral0)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }
}

#Preview {
    SettingFAQCell(question: "vaultSecurityFAQQuestion", answer: "setupVaultFAQQuestion")
}
