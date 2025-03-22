//
//  PasswordBackupOptionsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-21.
//

import SwiftUI

struct PasswordBackupOptionsView: View {
    var body: some View {
        ZStack {
            Background()
            content
        }
        .padding(24)
    }
    
    var content: some View {
        VStack(spacing: 36) {
            icon
            textContent
            buttons
        }
    }
    
    var icon: some View {
        Image(systemName: "person.badge.key")
            .font(.body28BrockmannMedium)
            .foregroundColor(.neutral0)
            .frame(width: 64, height: 64)
            .cornerRadius(16)
    }
    
    var textContent: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("doYouWantToAddPassword", comment: ""))
                .font(.body22BrockmannMedium)
            
            Text(NSLocalizedString("doYouWantToAddPasswordDescription", comment: ""))
                .font(.body14BrockmannMedium)
                .opacity(0.8)
        }
        .foregroundColor(.neutral0)
    }
    
    var buttons: some View {
        VStack(spacing: 12) {
            withoutPasswordButton
        }
    }
    
    var withoutPasswordButton: some View {
        FilledButton(title: "backupWithoutPassword")
    }
    
    var withPasswordButton: some View {
        FilledButton(
            title: "usePassword",
            textColor: .neutral0,
            background: .blue400
        )
    }
}

#Preview {
    PasswordBackupOptionsView()
}
