//
//  MayaCacaoStakingPreflight.swift
//  VultisigApp
//
//  Fresh signing-boundary availability check for CACAO pool transactions.
//

enum MayaCacaoStakingPreflightError: Error, Equatable {
    case halted
    case unavailable

    var localizationKey: String {
        switch self {
        case .halted:
            "mayaCacaoStakingHaltedWarning"
        case .unavailable:
            "mayaCacaoStakingUnavailableWarning"
        }
    }
}

struct MayaCacaoStakingPreflight {
    typealias AvailabilityReader = () async throws -> MayaNativeDepositAvailability

    private let readAvailability: AvailabilityReader

    init(
        readAvailability: @escaping AvailabilityReader = {
            try await MayaChainAPIService().getNativeDepositAvailability(shouldCache: false)
        }
    ) {
        self.readAvailability = readAvailability
    }

    func validate(_ transactionBuilder: TransactionBuilder) async throws {
        guard transactionBuilder is CacaoStakeTransactionBuilder
                || transactionBuilder is CacaoUnstakeTransactionBuilder else {
            return
        }

        do {
            guard try await readAvailability() == .available else {
                throw MayaCacaoStakingPreflightError.halted
            }
        } catch let error as MayaCacaoStakingPreflightError {
            throw error
        } catch {
            throw MayaCacaoStakingPreflightError.unavailable
        }
    }
}
