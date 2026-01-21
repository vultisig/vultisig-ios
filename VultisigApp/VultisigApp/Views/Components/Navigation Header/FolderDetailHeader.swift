//
//  FolderDetailHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-08.
//

import SwiftUI

struct FolderDetailHeader: View {
    let title: String
    @Binding var isEditing: Bool

    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
        .background(Theme.colors.bgPrimary)
    }

    var leadingAction: some View {
        NavigationBackButton()
    }

    var text: some View {
        Text(title)
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }

    var trailingAction: some View {
        Button {
            withAnimation {
                isEditing.toggle()
            }
        } label: {
            if isEditing {
                doneLabel
            } else {
                editIcon
            }
        }
    }

    var editIcon: some View {
        Image(systemName: "square.and.pencil")
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
    }

    var doneLabel: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
    }
}

#Preview {
    FolderDetailHeader(title: "Main", isEditing: .constant(true))
}
