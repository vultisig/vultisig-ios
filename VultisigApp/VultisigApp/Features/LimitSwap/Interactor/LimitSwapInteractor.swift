//
//  LimitSwapInteractor.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Wraps validation + memo-build failures into a single bag of validation errors
/// so the UI can surface them in one go without per-throw branching.
enum LimitSwapInteractorError: Error, Equatable {
    case validationFailed([LimitSwapValidationError])
}

/// Orchestrates limit-swap placement: fetches reference data, gates inputs
/// through validation + byte-cap, and persists placed orders.
///
/// The interactor takes primitive args rather than a `LimitSwapDraft` so the
/// Phase 1 view-model layer can adapt its draft into these calls without
/// coupling the interactor's tests to the SwiftUI form-state type. The draft
/// type lives in §5 and bridges to here.
protocol LimitSwapInteractor {

    /// Current market price (target natural units per source natural unit).
    func fetchMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal

    /// Validates inputs, builds the memo, asserts the byte cap. The single gate
    /// for "this limit order is placeable as-is."
    /// - Throws `LimitSwapInteractorError.validationFailed` if validation rejects
    ///   inputs; `LimitSwapMemoError.memoExceedsByteLimit` if the assembled memo
    ///   overflows the source-chain cap.
    func validateAndBuildMemo(
        inputs: LimitSwapInputs,
        sourceChainKind: ChainType
    ) throws -> String

    /// THORChain inbound vault address for the source chain (`BTC`, `ETH`, …).
    /// Returns `nil` if the chain is halted/paused.
    func fetchInboundAddress(forChainSymbol chainSymbol: String) async throws -> String?

    /// Persists a placed order on broadcast success.
    @MainActor
    @discardableResult
    func persistPlacedOrder(_ record: LimitOrderRecord, for vault: Vault) throws -> LimitOrder
}

struct DefaultLimitSwapInteractor: LimitSwapInteractor {

    private let quoteService: LimitSwapQuoteServiceProtocol
    private let storage: LimitOrderStorageService

    init(
        quoteService: LimitSwapQuoteServiceProtocol,
        storage: LimitOrderStorageService = LimitOrderStorageService()
    ) {
        self.quoteService = quoteService
        self.storage = storage
    }

    func fetchMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal {
        try await quoteService.fetchCurrentMarketPrice(
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            sourceDecimals: sourceDecimals,
            targetAsset: targetAsset,
            targetDecimals: targetDecimals,
            destinationAddress: destinationAddress
        )
    }

    func validateAndBuildMemo(
        inputs: LimitSwapInputs,
        sourceChainKind: ChainType
    ) throws -> String {
        let validationErrors = validateLimitSwapInputs(inputs)
        if !validationErrors.isEmpty {
            throw LimitSwapInteractorError.validationFailed(validationErrors)
        }
        let memo = try buildLimitSwapMemo(inputs)
        try assertMemoByteLength(memo, sourceChainKind: sourceChainKind)
        return memo
    }

    func fetchInboundAddress(forChainSymbol chainSymbol: String) async throws -> String? {
        try await quoteService.fetchInboundAddress(forChainSymbol: chainSymbol)
    }

    @MainActor
    @discardableResult
    func persistPlacedOrder(_ record: LimitOrderRecord, for vault: Vault) throws -> LimitOrder {
        try storage.persist(record, for: vault)
    }
}
