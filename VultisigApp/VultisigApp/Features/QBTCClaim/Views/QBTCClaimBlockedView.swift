//
//  QBTCClaimBlockedView.swift
//  VultisigApp
//
//  Banner shown when the claim flow can't proceed: SecureVault not
//  supported (v1), kill-switch closed, missing coin, unsupported BTC
//  address, or no claimable UTXOs.
//

import SwiftUI

struct QBTCClaimBlockedView: View {
    let reason: QBTCClaimBlockedReason

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(Theme.colors.alertWarning)
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconName: String {
        switch reason {
        case .secureVaultUnsupported, .unsupportedBtcAddress:
            return "exclamationmark.triangle.fill"
        case .killSwitchClosed, .utxoFetchFailed:
            return "lock.fill"
        case .missingCoin:
            return "questionmark.circle.fill"
        case .noUtxos:
            return "tray.fill"
        }
    }

    private var title: String {
        switch reason {
        case .secureVaultUnsupported:
            return "qbtcClaimFastVaultOnlyTitle".localized
        case .killSwitchClosed:
            return "qbtcClaimUnavailableTitle".localized
        case .missingCoin:
            return "qbtcClaimMissingCoinTitle".localized
        case .unsupportedBtcAddress:
            return "qbtcClaimUnsupportedAddressTitle".localized
        case .utxoFetchFailed:
            return "qbtcClaimFailedToLoadTitle".localized
        case .noUtxos:
            return "qbtcClaimNoUtxosTitle".localized
        }
    }

    private var detail: String {
        switch reason {
        case .secureVaultUnsupported:
            return "qbtcClaimFastVaultOnlyDetail".localized
        case .killSwitchClosed:
            return "qbtcClaimUnavailableDetail".localized
        case .missingCoin(let chainName):
            return String(format: "qbtcClaimMissingCoinDetail".localized, chainName)
        case .unsupportedBtcAddress(let detail):
            return detail
        case .utxoFetchFailed(let message):
            return message
        case .noUtxos:
            return "qbtcClaimNoUtxosDetail".localized
        }
    }
}
