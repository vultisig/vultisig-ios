//
//  Tooltip.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/02/2026.
//

import SwiftUI

struct Tooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textDark)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Color(hex: "F5F5F5"))
            .clipShape(TooltipShape())
    }
}

#Preview {
    Screen {
        Tooltip(
            text: "This occurs because the password is used to locally encrypt the backup file, similar to how a hard drive is encrypted. In the following step, you have the option to add a hint."
        )
        .padding(.horizontal, 24)
    }
}
