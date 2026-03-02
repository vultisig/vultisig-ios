//
//  ForegroundNotificationBannerModifier.swift
//  VultisigApp
//

import SwiftUI

private struct ForegroundNotificationBannerModifier: ViewModifier {
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var currentData: ForegroundNotificationData?
    @State private var isVisible: Bool = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var showBackground: Bool = false

    func body(content: Content) -> some View {
        VStack(spacing: 12) {
            if isVisible, let data = currentData {
                ForegroundNotificationBannerView(
                    data: data,
                    onTap: {
                        handleTap(data: data)
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
                .transition(.move(edge: .top))
            }

            content
        }
        .background(showBackground ? Theme.colors.bgPrimary.ignoresSafeArea() : nil)
        .onChange(of: pushNotificationManager.foregroundNotification) { _, newValue in
            guard let newValue else { return }
            show(data: newValue)
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                showBackground = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showBackground = false
                }
            }
        }
    }

    private func show(data: ForegroundNotificationData) {
        dismissTask?.cancel()

        currentData = data

        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            isVisible = true
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))

            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()

        withAnimation(.spring(duration: 0.3, bounce: 0)) {
            isVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            currentData = nil
            pushNotificationManager.foregroundNotification = nil
        }
    }

    private func handleTap(data: ForegroundNotificationData) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.Name("HandlePushNotification"),
                object: data.deeplinkURL
            )
        }
    }
}

extension View {
    func withForegroundNotificationBanner() -> some View {
        modifier(
            ForegroundNotificationBannerModifier()
        )
    }
}
