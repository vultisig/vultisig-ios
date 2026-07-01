//
//  SolanaStakeAccountParseTests.swift
//  VultisigAppTests
//
//  Pins jsonParsed -> SolanaStakeAccount parsing against a real mainnet
//  getProgramAccounts row (account 13JTejwnGAKdeSL4LvZnFjQwVYaJ9WseqMGGeSRTugn2,
//  captured live from api.vultisig.com/solana). The u64 fields arrive as
//  decimal strings and the deactivation sentinel is u64::MAX.
//

@testable import VultisigApp
import XCTest

final class SolanaStakeAccountParseTests: XCTestCase {

    /// A real `getProgramAccounts` (jsonParsed) row for an active delegation.
    private let delegatedRowJSON = """
    {
      "pubkey": "13JTejwnGAKdeSL4LvZnFjQwVYaJ9WseqMGGeSRTugn2",
      "account": {
        "data": {
          "parsed": {
            "info": {
              "meta": {
                "authorized": {
                  "staker": "5S2YKfAvT5r3NGmreYUqAskXFygNnmGsEu78hX9fGJg9",
                  "withdrawer": "5S2YKfAvT5r3NGmreYUqAskXFygNnmGsEu78hX9fGJg9"
                },
                "lockup": { "custodian": "11111111111111111111111111111111", "epoch": 0, "unixTimestamp": 0 },
                "rentExemptReserve": "2282880"
              },
              "stake": {
                "creditsObserved": 2204706881,
                "delegation": {
                  "activationEpoch": "732",
                  "deactivationEpoch": "18446744073709551615",
                  "stake": "1752172116988",
                  "voter": "2g2QU1NDRax6i2mKzRwgRfdBFoDkMC6bj7Zp5Q3i8sCq",
                  "warmupCooldownRate": 0.25
                }
              }
            },
            "type": "delegated"
          },
          "program": "stake",
          "space": 200
        },
        "executable": false,
        "lamports": 1752216432947,
        "owner": "Stake11111111111111111111111111111111111111",
        "rentEpoch": 18446744073709551615,
        "space": 200
      }
    }
    """

    /// An initialized-but-undelegated account: meta present, no `stake`.
    private let initializedRowJSON = """
    {
      "pubkey": "InitOnlyStakeAccount1111111111111111111111",
      "account": {
        "data": {
          "parsed": {
            "info": {
              "meta": {
                "authorized": { "staker": "OwnerAaaa", "withdrawer": "OwnerWwww" },
                "rentExemptReserve": "2282880"
              }
            },
            "type": "initialized"
          },
          "program": "stake",
          "space": 200
        },
        "lamports": 2282880,
        "owner": "Stake11111111111111111111111111111111111111",
        "executable": false,
        "rentEpoch": 0,
        "space": 200
      }
    }
    """

    private func decodeRow(_ json: String) throws -> SolanaStakeProgramAccount {
        try JSONDecoder().decode(SolanaStakeProgramAccount.self, from: Data(json.utf8))
    }

    func testDelegatedRowParsesToModel() throws {
        let row = try decodeRow(delegatedRowJSON)
        let account = try XCTUnwrap(SolanaStakeAccount(programAccount: row))

        XCTAssertEqual(account.pubkey, "13JTejwnGAKdeSL4LvZnFjQwVYaJ9WseqMGGeSRTugn2")
        XCTAssertEqual(account.lamports, 1_752_216_432_947)
        XCTAssertEqual(account.rentExemptReserve, 2_282_880)
        XCTAssertEqual(account.staker, "5S2YKfAvT5r3NGmreYUqAskXFygNnmGsEu78hX9fGJg9")
        XCTAssertEqual(account.withdrawer, "5S2YKfAvT5r3NGmreYUqAskXFygNnmGsEu78hX9fGJg9")

        let delegation = try XCTUnwrap(account.delegation)
        XCTAssertEqual(delegation.votePubkey, "2g2QU1NDRax6i2mKzRwgRfdBFoDkMC6bj7Zp5Q3i8sCq")
        XCTAssertEqual(delegation.activationEpoch, 732)
        XCTAssertEqual(delegation.stake, 1_752_172_116_988)
        // u64::MAX sentinel must round-trip exactly — a Double parse would lose it.
        XCTAssertEqual(delegation.deactivationEpoch, UInt64.max)
        XCTAssertTrue(delegation.isDeactivationSentinel)
    }

    func testActiveDelegationStateAfterActivationEpoch() throws {
        let account = try XCTUnwrap(SolanaStakeAccount(programAccount: try decodeRow(delegatedRowJSON)))
        // Current epoch (993) is well past activation (732) and not deactivating.
        XCTAssertEqual(account.activationState(currentEpoch: 993), .active)
    }

    func testActivatingInFirstEpoch() throws {
        let account = try XCTUnwrap(SolanaStakeAccount(programAccount: try decodeRow(delegatedRowJSON)))
        // At the activation epoch itself the stake is still warming up.
        XCTAssertEqual(account.activationState(currentEpoch: 732), .activating)
    }

    func testInitializedRowHasNoDelegationAndIsInactive() throws {
        let account = try XCTUnwrap(SolanaStakeAccount(programAccount: try decodeRow(initializedRowJSON)))
        XCTAssertNil(account.delegation)
        XCTAssertEqual(account.activationState(currentEpoch: 993), .inactive)
        XCTAssertEqual(account.rentExemptReserve, 2_282_880)
    }

    func testPubkeyOnlyRowIsSkipped() throws {
        // A dataSlice{0,0} base64 row carries no `parsed` — the model init
        // returns nil so the owner-scoped fetch can compactMap them out.
        let pubkeyOnlyJSON = """
        {
          "pubkey": "SomeStakeAccount",
          "account": {
            "data": ["", "base64"],
            "lamports": 1,
            "owner": "Stake11111111111111111111111111111111111111",
            "executable": false,
            "rentEpoch": 0,
            "space": 0
          }
        }
        """
        // base64 data is `["", "base64"]` (an array, not an object) — decoding
        // the row itself fails because `data` is modeled as an object. The
        // owner-scoped read uses jsonParsed, so this only documents that the
        // pubkey-only shape is a different decode path entirely.
        XCTAssertThrowsError(try decodeRow(pubkeyOnlyJSON))
    }
}
