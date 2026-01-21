//
//  VaultServerBackupViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/09/2025.
//

import Combine
import SwiftUI

final class VaultServerBackupViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var emailError: String?
    @Published var passwordError: String?
    @Published var requestError: String?
    @Published var isLoading = false

    @Published var showSuccess = false
    @Published var showAlert: Bool = false
    @Published private var alertError: ResendVaultShareError?

    @AppStorage("lastServerBackupRequestDate") private var lastServerBackupRequestDate: Double?
    private let waitingPeriodInSeconds: TimeInterval = 180

    @Published var currentTime = Date()
    private var timer: Timer?

    var cancellables = Set<AnyCancellable>()

    var buttonTitle: String {
        guard isInWaitPeriod else { return "next".localized }
        return String(format: "pleaseWaitMinutes".localized, arguments: [formattedRemainingWaitTime])
    }

    var alertErrorDescription: String? {
        guard let alertError else { return nil }
        switch alertError {
        case .tooManyRequests:
            return String(format: alertError.localizedDescription, formattedRemainingWaitTime)
        case .badRequest, .unknown:
            return alertError.localizedDescription
        }
    }

    var validForm: Bool {
        email.isNotEmpty &&
        password.isNotEmpty &&
        emailError == nil &&
        passwordError == nil &&
        !isLoading && !isInWaitPeriod
    }

    var validEmail: Bool {
        emailError == nil && email.isNotEmpty
    }

    var validPassword: Bool {
        passwordError == nil && password.isNotEmpty
    }

    let service = VultiServerService()

    func onLoad() {
        // Start timer if we're already in a wait period
        if isInWaitPeriod {
            startTimer()

            alertError = .tooManyRequests
            showAlert = true
        }

        $email
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] email in
                guard let self else { return }
                self.validate(email: email)
            }
            .store(in: &cancellables)

        $password
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] password in
                guard let self else { return }
                self.validate(password: password)
            }
            .store(in: &cancellables)
    }

    func validate(email: String) {
        if email.isEmpty || email.trimmingCharacters(in: .whitespaces).isEmpty {
            emailError = nil
        } else if !email.isValidEmail {
            emailError = "invalidEmailPleaseCheck".localized
        } else {
            emailError = nil
        }
    }

    func validate(password: String) {
        if password.isEmpty {
            passwordError = "passwordIsRequired".localized
        } else {
            passwordError = nil
        }
    }

    func requestServerVaultShare(vault: Vault) async {
        await MainActor.run {
            showAlert = false
            isLoading = true
        }

        do {
            try await service.resendVaultShare(request: ResendVaultShareRequest(pubKeyECDSA: vault.pubKeyECDSA, email: email, password: password))

            await MainActor.run {
                isLoading = false
                alertError = nil
                showSuccess = true
            }
        } catch {
            await MainActor.run {
                isLoading = false
                let vaultShareError = error as? ResendVaultShareError
                alertError = vaultShareError
                showAlert = true

                // Handle tooManyRequests error by setting the timestamp
                if vaultShareError == .tooManyRequests {
                    lastServerBackupRequestDate = Date().timeIntervalSince1970
                    startTimer()
                }
            }
        }
    }

    deinit {
        stopTimer()
    }
}

private extension VaultServerBackupViewModel {
    var isInWaitPeriod: Bool {
        guard let lastRequestDate = lastServerBackupRequestDate else { return false }
        let elapsed = currentTime.timeIntervalSince1970 - lastRequestDate
        return elapsed < waitingPeriodInSeconds
    }

    var remainingWaitTime: TimeInterval {
        guard let lastRequestDate = lastServerBackupRequestDate else { return 0 }
        let elapsed = currentTime.timeIntervalSince1970 - lastRequestDate
        return max(0, waitingPeriodInSeconds - elapsed)
    }

    var formattedRemainingWaitTime: String {
        let remaining = remainingWaitTime
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = Date()

            // Stop timer when wait period is over
            if !self.isInWaitPeriod {
                self.stopTimer()
                showAlert = false
                alertError = nil
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
