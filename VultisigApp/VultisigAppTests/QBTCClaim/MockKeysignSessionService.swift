//
//  MockKeysignSessionService.swift
//  VultisigAppTests
//
//  Test seam for `KeysignSessionServicing`. Records the sessions
//  passed to each method so tests can assert the QBTC drivers run on
//  the constructor-provided session (no derive-per-round) post the
//  single-session migration.
//

import Foundation
@testable import VultisigApp

// swiftlint:disable async_without_await
@MainActor
final class MockKeysignSessionService: KeysignSessionServicing {

    enum Call: Equatable {
        case registerAsParticipant(session: KeysignSessionInfo)
        case awaitKeysignStart(session: KeysignSessionInfo, timeout: TimeInterval)
        case pollSetupMessage(session: KeysignSessionInfo, messageID: String, timeout: TimeInterval)
    }

    /// Ordered record of method calls — tests assert order + session identity.
    private(set) var calls: [Call] = []

    /// Per-method error knobs. Each lets tests short-circuit before
    /// DKLS is reached while letting earlier calls succeed.
    var registerError: Error?
    var kickoffError: Error?
    var awaitError: Error?
    var pollError: Error?

    /// Optional participants list to return from `awaitKeysignStart`.
    var participantsToReturn: [String] = []
    /// Optional payload to return from `pollSetupMessage`.
    var setupMessageBodyToReturn: Data = Data()

    func registerAsParticipant(session: KeysignSessionInfo) async throws {
        calls.append(.registerAsParticipant(session: session))
        if let registerError { throw registerError }
    }

    func awaitKeysignStart(session: KeysignSessionInfo, timeout: TimeInterval) async throws -> [String] {
        calls.append(.awaitKeysignStart(session: session, timeout: timeout))
        if let awaitError { throw awaitError }
        return participantsToReturn
    }

    func pollSetupMessage(session: KeysignSessionInfo, messageID: String, timeout: TimeInterval) async throws -> Data {
        calls.append(.pollSetupMessage(session: session, messageID: messageID, timeout: timeout))
        if let pollError { throw pollError }
        return setupMessageBodyToReturn
    }
}

// swiftlint:enable async_without_await

struct MockSessionServiceError: Error {
    let message: String
}
