//
//  OpenGalleryButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-15.
//

#if os(iOS)
import SwiftUI

struct OpenButton: View {
    @State var buttonIcon: String
    @State var buttonLabel: String

    var body: some View {
        content
            .padding(.vertical, 5)
            .padding(.horizontal, 20)
            .frame(width: 170, height: 54)
            .background(Theme.colors.bgButtonPrimary)
            .cornerRadius(100)
    }

    var content: some View {
        HStack(spacing: 10) {
            Image(systemName: buttonIcon)
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.bgSurface1)

            Text(NSLocalizedString(buttonLabel, comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.bgSurface1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    HStack {
        OpenButton(buttonIcon: "photo.stack", buttonLabel: "uploadFromGallery")
        OpenButton(buttonIcon: "folder", buttonLabel: "uploadFromFiles")
    }
    .padding(.horizontal, 12)
}
#endif
