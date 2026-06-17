//
//  NoonApiService.swift
//  VultisigApp
//

import Foundation
import BigInt

enum NoonApiError: Error {
    case loanNotFound
    case missingField(String)
}

extension NoonApiError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .loanNotFound:
            return "Noon API did not include the configured loan"
        case .missingField(let field):
            return "Noon API response missing \(field)"
        }
    }
}

struct NoonVaultMetrics {
    let apy7dNetPercent: Decimal
    let tvlInUsd: Decimal
}

/// Product minimums in base units (6 dp), as reported by the loan terms:
/// deposit ≥ `minDeposit` (USDC), redeem ≥ `minRedeem` (naccUSDC). These are the
/// SDK-authoritative floors — NOT the vault's on-chain `MIN_AMOUNT_WEI` dust
/// floor.
struct NoonMinimums: Equatable {
    let minDeposit: BigInt
    let minRedeem: BigInt
}

/// Fetches APY (`back.noon.capital`) and TVL (`yield.accountable.capital`).
///
/// APY is read from `ir.7d.net.apy_pct` (the "7d net" figure, a string in the
/// payload). The `apy_pct` value lives under `ir`, NOT a top-level `7d` key.
struct NoonApiService {
    static let shared = NoonApiService()

    private let httpClient: HTTPClientProtocol
    private let loanAddress: String

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        loanAddress: String = NoonConstants.loanAddress
    ) {
        self.httpClient = httpClient
        self.loanAddress = loanAddress
    }

    func fetchApy() async throws -> Decimal {
        let response = try await httpClient.request(NoonAPI.vaults, responseType: NoonVaultsResponse.self)
        return try Self.apy(from: response.data, loanAddress: loanAddress)
    }

    func fetchTvl() async throws -> Decimal {
        let response = try await httpClient.request(
            NoonAPI.loan(loanAddress: loanAddress),
            responseType: NoonLoanResponse.self
        )
        guard let tvl = response.data.loanComputed.tvlInUsd else {
            throw NoonApiError.missingField("loan_computed.tvl_in_usd")
        }
        return Decimal(tvl)
    }

    func fetchMetrics() async throws -> NoonVaultMetrics {
        async let apyTask = fetchApy()
        async let tvlTask = fetchTvl()
        return NoonVaultMetrics(apy7dNetPercent: try await apyTask, tvlInUsd: try await tvlTask)
    }

    /// The product minimums from the loan terms (`on_chain_loan.loan.loan`). The
    /// `fallback` is used for either field the payload omits, so a partial
    /// response can't drop a floor to zero. This is the authoritative deposit /
    /// redeem floor — the vault's `MIN_AMOUNT_WEI` is only a dust floor and is
    /// NOT used here.
    func fetchMinimums(fallback: NoonMinimums) async throws -> NoonMinimums {
        let response = try await httpClient.request(
            NoonAPI.loan(loanAddress: loanAddress),
            responseType: NoonLoanResponse.self
        )
        return Self.minimums(from: response.data, fallback: fallback)
    }

    // MARK: - Decoding

    /// Filters the vaults list by `loan_address` and reads `ir.7d.net.apy_pct`.
    static func apy(from response: NoonVaultsResponse, loanAddress: String) throws -> Decimal {
        let target = response.vaults.first {
            $0.loanAddress.lowercased() == loanAddress.lowercased()
        }
        guard let target else { throw NoonApiError.loanNotFound }
        guard let apyString = target.ir?.sevenDay?.net?.apyPct,
              let apy = Decimal(string: apyString) else {
            throw NoonApiError.missingField("ir.7d.net.apy_pct")
        }
        return apy
    }

    /// Reads `on_chain_loan.loan.loan.minDeposit` / `.minRedeem`, falling back to
    /// `fallback` per-field when the response omits it. Pure so the fallback
    /// behaviour is unit-testable.
    static func minimums(from response: NoonLoanResponse, fallback: NoonMinimums) -> NoonMinimums {
        let loan = response.onChainLoan?.loan?.loan
        return NoonMinimums(
            minDeposit: loan?.minDeposit?.value ?? fallback.minDeposit,
            minRedeem: loan?.minRedeem?.value ?? fallback.minRedeem
        )
    }
}

// MARK: - Response models

struct NoonVaultsResponse: Decodable {
    let vaults: [NoonVaultEntry]
}

struct NoonVaultEntry: Decodable {
    let loanAddress: String
    let ir: NoonInterestRate?

    enum CodingKeys: String, CodingKey {
        case loanAddress = "loan_address"
        case ir
    }
}

struct NoonInterestRate: Decodable {
    let sevenDay: NoonRateWindow?

    enum CodingKeys: String, CodingKey {
        case sevenDay = "7d"
    }
}

struct NoonRateWindow: Decodable {
    let net: NoonRateValue?
}

struct NoonRateValue: Decodable {
    let apyPct: String?

    enum CodingKeys: String, CodingKey {
        case apyPct = "apy_pct"
    }
}

struct NoonLoanResponse: Decodable {
    let loanComputed: NoonLoanComputed
    let onChainLoan: NoonOnChainLoan?

    enum CodingKeys: String, CodingKey {
        case loanComputed = "loan_computed"
        case onChainLoan = "on_chain_loan"
    }
}

struct NoonLoanComputed: Decodable {
    let tvlInUsd: Double?

    enum CodingKeys: String, CodingKey {
        case tvlInUsd = "tvl_in_usd"
    }
}

/// Nested loan terms: `on_chain_loan.loan.loan`. The inner `loan.loan` mirrors the
/// SDK's hardcoded `minDepositAssets`/`minRedeem` floors.
struct NoonOnChainLoan: Decodable {
    let loan: NoonLoanWrapper?
}

struct NoonLoanWrapper: Decodable {
    let loan: NoonLoanTerms?
}

struct NoonLoanTerms: Decodable {
    let minDeposit: NoonBaseUnits?
    let minRedeem: NoonBaseUnits?
}

/// A base-unit integer that the API may encode as either a JSON number or a
/// numeric string. Decodes to `BigInt` either way; a non-numeric value yields
/// `nil` (the caller then uses its fallback rather than trapping).
struct NoonBaseUnits: Decodable {
    let value: BigInt

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let parsed = BigInt(string) {
            value = parsed
            return
        }
        if let number = try? container.decode(Int64.self) {
            value = BigInt(number)
            return
        }
        throw NoonApiError.missingField("on_chain_loan.loan.loan minimum")
    }
}
