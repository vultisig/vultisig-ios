//
//  VaultNotificationOptInSheet.swift
//  VultisigApp
//

import SwiftUI

struct VaultNotificationOptInSheet: View {
    let vault: Vault
    @Binding var isPresented: Bool
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    var body: some View {
        VStack(spacing: 24) {
            Text("enableNotificationsForVault".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            VaultNotificationToggleRow(vault: vault)

            Spacer()

            PrimaryButton(title: "done") {
                isPresented = false
            }
        }
        .padding(24)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .background(Theme.colors.bgPrimary)
    }
}

#if DEBUG
#Preview {
    VaultNotificationOptInSheet(
        vault: Vault.example,
        isPresented: .constant(true)
    )
    .environmentObject(
        MockPushNotificationManager(permissionGranted: true)
            as PushNotificationManager
    )
}
#endif
