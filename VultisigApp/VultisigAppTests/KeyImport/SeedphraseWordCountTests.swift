//
//  SeedphraseWordCountTests.swift
//  VultisigAppTests
//

import XCTest
import WalletCore
@testable import VultisigApp

final class SeedphraseWordCountTests: XCTestCase {
    private func zeroEntropyPhrase(words: Int, checksumWord: String) -> String {
        (Array(repeating: "abandon", count: words - 1) + [checksumWord]).joined(separator: " ")
    }

    func testSupportedLengthsAreEveryBip39Length() {
        XCTAssertEqual(SeedphraseWordCount.supported, [12, 15, 18, 21, 24])
        for count in [12, 15, 18, 21, 24] {
            XCTAssertTrue(SeedphraseWordCount.isSupported(count), "\(count)")
        }
    }

    func testUnsupportedCountsAreRejected() {
        for count in [0, 1, 11, 13, 14, 16, 17, 19, 20, 22, 23, 25, 36] {
            XCTAssertFalse(SeedphraseWordCount.isSupported(count), "\(count)")
        }
    }

    func testTargetLengthRoundsUpToNextSupportedLength() {
        XCTAssertEqual(SeedphraseWordCount.targetLength(for: 0), 12)
        XCTAssertEqual(SeedphraseWordCount.targetLength(for: 12), 12)
        XCTAssertEqual(SeedphraseWordCount.targetLength(for: 13), 15)
        XCTAssertEqual(SeedphraseWordCount.targetLength(for: 16), 18)
        XCTAssertEqual(SeedphraseWordCount.targetLength(for: 19), 21)
        XCTAssertEqual(SeedphraseWordCount.targetLength(for: 22), 24)
        XCTAssertEqual(SeedphraseWordCount.targetLength(for: 30), 24)
    }

    func testWalletCoreAcceptsEveryLengthAndDerivesAWallet() {
        let phrases = [
            zeroEntropyPhrase(words: 12, checksumWord: "about"),
            zeroEntropyPhrase(words: 15, checksumWord: "address"),
            zeroEntropyPhrase(words: 18, checksumWord: "agent"),
            zeroEntropyPhrase(words: 21, checksumWord: "admit"),
            zeroEntropyPhrase(words: 24, checksumWord: "art")
        ]
        for phrase in phrases {
            let count = phrase.split(separator: " ").count
            XCTAssertTrue(SeedphraseWordCount.isSupported(count))
            XCTAssertTrue(Mnemonic.isValid(mnemonic: phrase), "\(count) words")
            XCTAssertNotNil(HDWallet(mnemonic: phrase, passphrase: ""), "\(count) words")
        }
    }

    func testBadChecksumAtNewLengthIsInvalid() {
        let phrase = zeroEntropyPhrase(words: 15, checksumWord: "abandon")
        XCTAssertFalse(Mnemonic.isValid(mnemonic: phrase))
    }
}
