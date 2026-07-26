//
//  SolanaServiceAtaFallbackTests.swift
//  VultisigAppTests
//
//  Covers `SolanaService.fetchTokenAssociatedAccountByOwner` recovering from a
//  transient `getTokenAccountsByOwner` failure. When the primary indexer lookup
//  THROWS (a momentary RPC/node error, not an empty index) the method now falls
//  through to the same deterministic ATA derivation + `getAccountInfo` existence
//  probe used for the empty-result case, so a derivable/existing account still
//  resolves and the send does not fail. A genuinely-missing account still yields
//  the not-found result, and a successful primary lookup is unchanged.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class SolanaServiceAtaFallbackTests: XCTestCase {

    /// Classic SPL token program — the owner reported for a standard ATA.
    private let tokenProgramId = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    /// Token-2022 program id (mirrors `SolanaService.TOKEN_PROGRAM_ID_2022`).
    private let token2022ProgramId = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

    private let ownerAddress = "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3"
    private let mintAddress = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    private func makeService(_ stub: SolanaAtaStubHTTPClient) -> SolanaService {
        SolanaService(
            resolver: NoOverrideResolver(),
            httpClient: stub,
            broadcastRetryBackoff: .zero
        )
    }

    /// The classic-SPL ATA the fallback derives for our owner/mint pair.
    private func derivedDefaultAta() throws -> String {
        let address = try XCTUnwrap(WalletCore.SolanaAddress(string: ownerAddress))
        return try XCTUnwrap(address.defaultTokenAddress(tokenMintAddress: mintAddress))
    }

    /// The Token-2022 ATA the fallback derives for our owner/mint pair.
    private func derivedToken2022Ata() throws -> String {
        let address = try XCTUnwrap(WalletCore.SolanaAddress(string: ownerAddress))
        return try XCTUnwrap(address.token2022Address(tokenMintAddress: mintAddress))
    }

    // (a) Primary lookup throws, but the derived classic-SPL ATA exists on-chain:
    //     the fallback probe finds it and returns it instead of failing the send.
    func testThrowingPrimaryLookupReturnsDerivedExistingAta() async throws {
        let defaultAta = try derivedDefaultAta()
        let stub = SolanaAtaStubHTTPClient(
            primaryOutcome: .failure,
            existingAccounts: [defaultAta: tokenProgramId]
        )
        let service = makeService(stub)

        let (account, isToken2022) = try await service.fetchTokenAssociatedAccountByOwner(
            for: ownerAddress,
            mintAddress: mintAddress
        )

        XCTAssertEqual(account, defaultAta)
        XCTAssertFalse(isToken2022)
        XCTAssertEqual(stub.tokenAccountsByOwnerCallCount, 1)
        // Only the classic-SPL probe is needed; it exists, so we stop there.
        XCTAssertEqual(stub.accountInfoCallCount, 1)
    }

    // (a') Primary lookup throws and only the Token-2022 ATA exists: the fallback
    //      probes both derivations and returns the Token-2022 account.
    func testThrowingPrimaryLookupReturnsDerivedToken2022Ata() async throws {
        let token2022Ata = try derivedToken2022Ata()
        let stub = SolanaAtaStubHTTPClient(
            primaryOutcome: .failure,
            existingAccounts: [token2022Ata: token2022ProgramId]
        )
        let service = makeService(stub)

        let (account, isToken2022) = try await service.fetchTokenAssociatedAccountByOwner(
            for: ownerAddress,
            mintAddress: mintAddress
        )

        XCTAssertEqual(account, token2022Ata)
        XCTAssertTrue(isToken2022)
        XCTAssertEqual(stub.tokenAccountsByOwnerCallCount, 1)
        // Classic-SPL probe misses, Token-2022 probe hits: two existence checks.
        XCTAssertEqual(stub.accountInfoCallCount, 2)
    }

    // (b) Primary lookup throws and neither derived ATA exists: the account is
    //     genuinely missing, so the not-found result is returned (not an error).
    func testThrowingPrimaryLookupWithNoExistingAtaReturnsNotFound() async throws {
        let stub = SolanaAtaStubHTTPClient(primaryOutcome: .failure)
        let service = makeService(stub)

        let (account, isToken2022) = try await service.fetchTokenAssociatedAccountByOwner(
            for: ownerAddress,
            mintAddress: mintAddress
        )

        XCTAssertEqual(account, "")
        XCTAssertFalse(isToken2022)
        XCTAssertEqual(stub.tokenAccountsByOwnerCallCount, 1)
        // Both derivations are probed and both miss.
        XCTAssertEqual(stub.accountInfoCallCount, 2)
    }

    // Success path unchanged: a non-empty primary lookup returns that account
    // immediately, without probing the derived ATAs.
    func testSuccessfulPrimaryLookupReturnsAccountWithoutProbing() async throws {
        let indexedPubkey = "9gANMngbGUmAaLXL1RC3JdiaLjRowJXNbzCTh53ht7mq"
        let stub = SolanaAtaStubHTTPClient(
            primaryOutcome: .account(pubkey: indexedPubkey, ownerProgram: tokenProgramId)
        )
        let service = makeService(stub)

        let (account, isToken2022) = try await service.fetchTokenAssociatedAccountByOwner(
            for: ownerAddress,
            mintAddress: mintAddress
        )

        XCTAssertEqual(account, indexedPubkey)
        XCTAssertFalse(isToken2022)
        XCTAssertEqual(stub.tokenAccountsByOwnerCallCount, 1)
        // No fallback: the derived-ATA existence probe must not run.
        XCTAssertEqual(stub.accountInfoCallCount, 0)
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

/// Routes Solana JSON-RPC calls by method so the ATA fallback can be exercised
/// deterministically: the primary `getTokenAccountsByOwner` returns a scripted
/// outcome (throw / empty / a matching account), and `getAccountInfo` reports an
/// address as existing only when it is in `existingAccounts`.
private final class SolanaAtaStubHTTPClient: HTTPClientProtocol {

    enum PrimaryOutcome {
        /// Transient RPC/node failure — the request itself throws.
        case failure
        /// Indexer returns no matching token account.
        case empty
        /// Indexer returns a matching token account.
        case account(pubkey: String, ownerProgram: String)
    }

    private let primaryOutcome: PrimaryOutcome
    /// getAccountInfo existence probe: address -> owning token-program id.
    private let existingAccounts: [String: String]

    private(set) var tokenAccountsByOwnerCallCount = 0
    private(set) var accountInfoCallCount = 0

    init(primaryOutcome: PrimaryOutcome, existingAccounts: [String: String] = [:]) {
        self.primaryOutcome = primaryOutcome
        self.existingAccounts = existingAccounts
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let api = target as? SolanaAPI else {
            XCTFail("unexpected non-Solana target in ATA fallback test")
            throw HTTPError.invalidResponse
        }

        let json: String
        switch api.rpcMethod {
        case .getTokenAccountsByOwner:
            tokenAccountsByOwnerCallCount += 1
            switch primaryOutcome {
            case .failure:
                throw URLError(.timedOut)
            case .empty:
                json = Self.tokenAccountsEnvelope(valueJSON: "[]")
            case let .account(pubkey, ownerProgram):
                json = Self.tokenAccountsEnvelope(
                    valueJSON: "[\(Self.tokenAccountJSON(pubkey: pubkey, ownerProgram: ownerProgram))]"
                )
            }
        case let .getAccountInfo(address):
            accountInfoCallCount += 1
            if let owner = existingAccounts[address] {
                json = #"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":{"owner":"\#(owner)"}}}"#
            } else {
                json = #"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":null}}"#
            }
        default:
            XCTFail("unexpected RPC method in ATA fallback test")
            throw HTTPError.invalidResponse
        }

        return Self.httpResponse(json: json)
    }

    private static func tokenAccountsEnvelope(valueJSON: String) -> String {
        #"{"jsonrpc":"2.0","id":1,"result":{"context":{"apiVersion":"2.0.0","slot":1},"value":\#(valueJSON)}}"#
    }

    private static func tokenAccountJSON(pubkey: String, ownerProgram: String) -> String {
        """
        {
          "pubkey": "\(pubkey)",
          "account": {
            "data": {
              "parsed": {
                "info": {
                  "isNative": false,
                  "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                  "owner": "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3",
                  "state": "initialized",
                  "tokenAmount": {
                    "amount": "0",
                    "decimals": 6,
                    "uiAmount": 0,
                    "uiAmountString": "0"
                  }
                },
                "type": "account"
              },
              "program": "spl-token",
              "space": 165
            },
            "executable": false,
            "lamports": 2039280,
            "owner": "\(ownerProgram)",
            "rentEpoch": 18446744073709551615,
            "space": 165
          }
        }
        """
    }

    private static func httpResponse(json: String) -> HTTPResponse<Data> {
        let response = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }
}
