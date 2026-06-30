//
//  StakingValidatorProjectionTests.swift
//  VultisigAppTests
//
//  Pins the chain-agnostic `StakingValidator` display projection the shared
//  picker renders — name/subtitle/commission/avatar mapping + search terms — for
//  both the Cosmos and Solana validator types. Locale-safe values (scaled
//  power/stake < 1000) keep the subline grouping-separator-independent.
//

@testable import VultisigApp
import Foundation
import XCTest

final class StakingValidatorProjectionTests: XCTestCase {

    // MARK: - Cosmos

    func testCosmosProjectionUsesMonikerAndKeybaseAvatar() {
        let validator = CosmosValidator(
            operatorAddress: "terravaloper1aaa",
            moniker: "Allnodes",
            commission: 0.05,
            jailed: false,
            status: .bonded,
            votingPower: 250_000_000, // 250 at 6 decimals
            identity: "ABCDEF0123456789"
        )
        let projection = validator.makeStakingValidator(ticker: "LUNA", decimals: 6)

        XCTAssertEqual(projection.name, "Allnodes")
        XCTAssertEqual(projection.subtitle, "250 LUNA")
        XCTAssertEqual(projection.commission, "5%")
        XCTAssertEqual(projection.avatar, .keybase(identity: "ABCDEF0123456789", monogram: "A"))
        XCTAssertEqual(validator.searchTerms, ["Allnodes", "terravaloper1aaa"])
    }

    func testCosmosEmptyMonikerFallsBackToTruncatedAddress() {
        let validator = CosmosValidator(
            operatorAddress: "terravaloper1abcdefghijklmnop",
            moniker: "",
            commission: 0.123,
            jailed: false,
            status: .bonded,
            votingPower: 0
        )
        let projection = validator.makeStakingValidator(ticker: "LUNA", decimals: 6)

        XCTAssertEqual(projection.name, "terraval…mnop")
        XCTAssertEqual(projection.commission, "12.3%")
        XCTAssertEqual(projection.avatar, .keybase(identity: nil, monogram: "T"))
    }

    // MARK: - Solana

    func testSolanaProjectionUsesDisplayNameAndLogoAvatar() {
        var validator = SolanaValidator(
            votePubkey: "9gANMngbGUmAaLXL1RC3JdiaLjRowJXNbzCTh53ht7mq",
            nodePubkey: "Node",
            activatedStake: 5_000_000_000, // 5 at 9 decimals
            commission: 7,
            epochVoteAccount: true,
            isDelinquent: false
        )
        validator.metadata = ValidatorMetadata(name: "Yurbason", logoURL: "https://media.stakewiz.com/yurbason.png")
        let projection = validator.makeStakingValidator(ticker: "SOL", decimals: 9)

        XCTAssertEqual(projection.name, "Yurbason")
        XCTAssertEqual(projection.subtitle, "5 SOL")
        XCTAssertEqual(projection.commission, "7%")
        XCTAssertEqual(
            projection.avatar,
            .logo(url: URL(string: "https://media.stakewiz.com/yurbason.png"), monogram: "Y")
        )
        XCTAssertEqual(validator.searchTerms, ["Yurbason", "9gANMngbGUmAaLXL1RC3JdiaLjRowJXNbzCTh53ht7mq"])
    }

    func testSolanaEmptyMetadataFallsBackToTruncatedPubkeyMonogram() {
        let validator = SolanaValidator(
            votePubkey: "9gANMngbGUmAaLXL1RC3JdiaLjRowJXNbzCTh53ht7mq",
            nodePubkey: "Node",
            activatedStake: 0,
            commission: 0,
            epochVoteAccount: true,
            isDelinquent: false
        )
        let projection = validator.makeStakingValidator(ticker: "SOL", decimals: 9)

        XCTAssertEqual(projection.name, "9gAN…t7mq")
        XCTAssertEqual(projection.commission, "0%")
        XCTAssertEqual(projection.avatar, .logo(url: nil, monogram: "9"))
    }
}
