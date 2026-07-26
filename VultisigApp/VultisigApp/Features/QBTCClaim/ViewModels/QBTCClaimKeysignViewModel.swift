//
//  QBTCClaimKeysignViewModel.swift
//  VultisigApp
//
//  Drives the QBTC claim BTC ECDSA round + proof generation via
//  `QBTCClaimOrchestrator`. Constructed by the keysign screen; navigates
//  to `QBTCClaimRoute.done` on success, surfaces `errorTitle` for retry
//  on failure. It is a thin orchestrator driver — the keysign UI is
//  provided by `SendCryptoKeysignView`, not the shared `KeysignView`.
//

import Foundation
import OSLog
import SwiftUI

@MainActor
final class QBTCClaimKeysignViewModel: ObservableObject {
    let vault: Vault
    let btcCoin: Coin
    let qbtcCoin: Coin
    let selectedUtxos: [ClaimableUtxo]
    let fastVaultPassword: String?
    let session: KeysignSessionInfo?
    let participants: [String]

    @Published private(set) var runResult: QBTCClaimRunResult?
    @Published private(set) var errorTitle: String?
    @Published private(set) var isError: Bool = false

    private let orchestratorFactory: () -> QBTCClaimOrchestrator
    private var orchestrator: QBTCClaimOrchestrator?
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-claim-keysign-vm")

    init(
        vault: Vault,
        btcCoin: Coin,
        qbtcCoin: Coin,
        selectedUtxos: [ClaimableUtxo],
        fastVaultPassword: String?,
        session: KeysignSessionInfo?,
        participants: [String],
        orchestratorFactory: (() -> QBTCClaimOrchestrator)? = nil
    ) {
        self.vault = vault
        self.btcCoin = btcCoin
        self.qbtcCoin = qbtcCoin
        self.selectedUtxos = selectedUtxos
        self.fastVaultPassword = fastVaultPassword
        self.session = session
        self.participants = participants
        if let orchestratorFactory {
            self.orchestratorFactory = orchestratorFactory
        } else if let session {
            let participants = participants
            self.orchestratorFactory = {
                QBTCClaimOrchestrator.makeSecureVault(
                    session: session,
                    participants: participants
                )
            }
        } else {
            self.orchestratorFactory = { QBTCClaimOrchestrator.makeFastVault() }
        }
    }

    func run() async {
        let orchestrator = orchestratorFactory()
        self.orchestrator = orchestrator
        let input = QBTCClaimRunInput(
            vault: vault,
            btcCoin: btcCoin,
            qbtcCoin: qbtcCoin,
            utxos: selectedUtxos,
            fastVaultPassword: fastVaultPassword ?? ""
        )
        await orchestrator.run(input)
        switch orchestrator.phase {
        case .done(let result):
            runResult = result
        case .failed(let message):
            errorTitle = message
            isError = true
        default:
            break
        }
    }

    func retry() async {
        isError = false
        errorTitle = nil
        await run()
    }
}
