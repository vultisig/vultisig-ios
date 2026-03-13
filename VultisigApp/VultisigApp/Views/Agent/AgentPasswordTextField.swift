//
//  AgentPasswordTextField.swift
//  VultisigApp
//

import SwiftUI

struct AgentPasswordTextField: View {
    @Binding var password: String
    var errorMessage: String?
    var isAuthorizing: Bool
    var isFocused: FocusState<Bool>.Binding
    var onClear: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(errorMessage ?? "agentAuthorizeAgent".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(errorMessage != nil ? Theme.colors.alertError : Theme.colors.alertInfo)

            HStack(spacing: 12) {
                SecureField("agentPasswordPlaceholder".localized, text: $password)
                    .textFieldStyle(.plain)
                    .font(Theme.fonts.bodyMMedium)
                    .focused(isFocused)
                    .onSubmit { onSubmit() }

                Button {
                    password = ""
                    onClear()
                    isFocused.wrappedValue = false
                } label: {
                    Icon(
                        named: "circle-x-fill",
                        color: Theme.colors.textTertiary,
                        size: 16
                    )
                }.showIf(password != .empty)

                Button {
                    onSubmit()
                } label: {
                    Icon(named: "lock-keyhole-open", color: Theme.colors.textSecondary, size: 20)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Theme.colors.buttonsCTAPrimary)
                                .stroke(Theme.colors.primaryAccent3, lineWidth: 1)
                        )
                }
                .disabled(password.isEmpty || isAuthorizing)
            }
            .frame(height: 70)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .inset(by: 0.5)
                        .fill(Theme.colors.bgSurface1)
                        .stroke(Theme.colors.borderLight, lineWidth: 1)

                    innerShadows
                }
            )
        }
        .padding(.horizontal, 16)
    }

    private var innerShadows: some View {
        let shape = RoundedRectangle(cornerRadius: 24)

        return ZStack {
            // inset 0px 20px 20px rgba(0,0,255,0.1) — blue glow from top
            shape
                .stroke(Color(hex: "0000FF").opacity(0.1), lineWidth: 40)
                .offset(y: 20)
                .blur(radius: 10)

            // inset 0px -2px 4px rgba(206,213,255,0.1) — subtle light from bottom
            shape
                .stroke(Color(hex: "CED5FF").opacity(0.1), lineWidth: 8)
                .offset(y: -2)
                .blur(radius: 2)

            // inset 0px 2px 8px rgba(137,170,255,0.1) — subtle light from top
            shape
                .stroke(Color(hex: "89AAFF").opacity(0.1), lineWidth: 16)
                .offset(y: 2)
                .blur(radius: 4)
        }
        .clipShape(shape)
    }
}
