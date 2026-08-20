//
//  THORChainWasmExecutionPreflight.swift
//  VultisigApp
//
//  Fresh signing-boundary availability check for THORChain WASM transactions.
//

enum THORChainWasmExecutionPreflightError: Error, Equatable {
    case halted
    case unavailable

    var localizationKey: String {
        switch self {
        case .halted:
            "thorchainWasmStakingHaltedWarning"
        case .unavailable:
            "thorchainWasmStakingUnavailableWarning"
        }
    }
}

struct THORChainWasmExecutionPreflight {
    private let availabilityProvider: THORChainWasmExecutionAvailabilityProviding

    init(
        availabilityProvider: THORChainWasmExecutionAvailabilityProviding = ThorchainService.shared
    ) {
        self.availabilityProvider = availabilityProvider
    }

    func validate(_ transactionBuilder: TransactionBuilder) async throws {
        guard transactionBuilder.coin.chain == .thorChain else { return }

        let contractAddresses = transactionBuilder.wasmContractAddressesForPreflight
        guard !contractAddresses.isEmpty else { return }

        let availabilities = await availabilityProvider.fetchWasmExecutionAvailabilities(
            for: contractAddresses
        )
        let states = contractAddresses.map { availabilities[$0] ?? .unavailable }

        if states.contains(.halted) {
            throw THORChainWasmExecutionPreflightError.halted
        }
        if states.contains(.unavailable) {
            throw THORChainWasmExecutionPreflightError.unavailable
        }
    }
}
