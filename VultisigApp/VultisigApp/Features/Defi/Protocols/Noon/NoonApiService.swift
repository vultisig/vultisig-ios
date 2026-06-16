//
//  NoonApiService.swift
//  VultisigApp
//

import Foundation

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

    enum CodingKeys: String, CodingKey {
        case loanComputed = "loan_computed"
    }
}

struct NoonLoanComputed: Decodable {
    let tvlInUsd: Double?

    enum CodingKeys: String, CodingKey {
        case tvlInUsd = "tvl_in_usd"
    }
}
