//
//  ErrorView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/08/2025.
//

import SwiftUI

struct ErrorScreen: View {
    let type: ErrorView.ErrorType
    let title: String
    let description: String
    let buttonTitle: String
    var action: () -> Void

    var body: some View {
        Screen {
            ErrorView(
                type: type,
                title: title,
                description: description,
                buttonTitle: buttonTitle,
                action: action
            )
        }
    }
}

struct ErrorView: View {
    let type: ErrorType
    let title: String
    let description: String
    let buttonTitle: String
    var action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(color)
                    .background(Image("CirclesBackground"))
                    .padding(.bottom, 12)
                Text(title)
                    .foregroundStyle(color)
                    .font(Theme.fonts.title2)
                    .multilineTextAlignment(.center)
                Text(description)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                    .frame(maxWidth: .infinity, maxHeight: description.isNotEmpty ? 40 : 0, alignment: .top)
                    .multilineTextAlignment(.center)
                PrimaryButton(
                    title: buttonTitle,
                    type: .secondary,
                    action: action
                )
            }
            Spacer()
            Text(Bundle.main.appVersionString)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)
        }
        .padding(.vertical, 12)
    }
}

private extension ErrorView {
    var icon: String {
        switch type {
        case .warning:
            return "exclamationmark.circle.fill"
        case .alert:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch type {
        case .alert:
            Theme.colors.alertError
        case .warning:
            Theme.colors.alertWarning
        }
    }
}

extension ErrorView {
    enum ErrorType {
        case alert
        case warning
    }
}

#Preview {
    ErrorView(
        type: .warning,
        title: "Transaction failed",
        description: "Transaction failed due to X reason",
        buttonTitle: "Try again"
    ) {}
}
