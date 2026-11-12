//
//  VaultSetupStepIcon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/02/2026.
//

import SwiftUI

struct VaultSetupStepIcon: View {
    enum Size {
        /// 44pt circle, 24pt glyph.
        case regular
        /// 44pt circle, 16pt glyph.
        case small
        /// 36pt circle, 20pt glyph.
        case compact

        var iconSize: CGFloat {
            switch self {
            case .regular: 24
            case .small: 16
            case .compact: 20
            }
        }

        var padding: CGFloat {
            switch self {
            case .regular: 10
            case .small: 14
            case .compact: 8
            }
        }
    }

    let state: VaultSetupStepState
    let icon: ImageResource
    let size: Size

    init(state: VaultSetupStepState, icon: ImageResource, size: Size = .regular) {
        self.state = state
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Icon(icon, color: iconColor, size: size.iconSize)
            .padding(size.padding)
            .if(state == .active) {
                $0.background(alignment: .bottom) { shadowView }
            }
            .background(
                Circle()
                    .inset(by: 1.5)
                    .stroke(borderColor, lineWidth: 2)
                    .fill(bgColor)
            )
            .clipShape(Circle())
    }

    var shadowView: some View {
        Rectangle().fill(Color(hex: "0C4EFF"))
            .frame(width: 16, height: 8)
            .blur(radius: 9.5)
    }

    var iconColor: Color {
        switch state {
        case .valid:
            Theme.colors.alertSuccess
        case .active:
            Theme.colors.primaryAccent4
        case .inactive:
            Theme.colors.borderLight
        }
    }

    var bgColor: Color {
        switch state {
        case .valid:
            Theme.colors.alertSuccess.opacity(0.05)
        case .active, .inactive:
            Color(hex: "03132C")
        }
    }

    var borderColor: Color {
        switch state {
        case .valid:
            .clear
        case .active:
            .white.opacity(0.2)
        case .inactive:
            Theme.colors.borderLight
        }
    }
}

enum VaultSetupStepState: Equatable {
    case valid
    case active
    case inactive
}

#Preview {
    Screen {
        VStack {
            VaultSetupStepIcon(state: .valid, icon: .feather)
            VaultSetupStepIcon(state: .active, icon: .envelopeFilled)
            VaultSetupStepIcon(state: .inactive, icon: .lockPassword)
        }
    }
}
