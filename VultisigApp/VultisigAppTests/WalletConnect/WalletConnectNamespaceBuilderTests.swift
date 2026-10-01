//
//  WalletConnectNamespaceBuilderTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class WalletConnectNamespaceBuilderTests: XCTestCase {
    func testBuildsEVMApprovalWithCAIP10AccountsForRequiredChains() throws {
        let approval = try WalletConnectEVMNamespaceAdapter().buildApproval(
            requiredNamespaces: [
                WalletConnectNamespaceRequest(
                    namespace: "eip155",
                    chains: ["eip155:1", "eip155:8453"],
                    methods: ["eth_sendTransaction", "personal_sign"],
                    events: ["accountsChanged", "chainChanged"]
                )
            ],
            optionalNamespaces: [
                WalletConnectNamespaceRequest(
                    namespace: "eip155",
                    chains: ["eip155:137"],
                    methods: ["eth_signTypedData_v4", "wallet_switchEthereumChain"],
                    events: ["message"]
                )
            ],
            accounts: [
                WalletConnectEVMAccount(chainReference: "eip155:1", address: "0x111"),
                WalletConnectEVMAccount(chainReference: "eip155:8453", address: "0x222"),
                WalletConnectEVMAccount(chainReference: "eip155:137", address: "0x333")
            ]
        )

        XCTAssertEqual(approval.chains, ["eip155:1", "eip155:8453", "eip155:137"])
        XCTAssertEqual(approval.methods, ["eth_sendTransaction", "personal_sign", "eth_signTypedData_v4"])
        XCTAssertEqual(approval.events, ["accountsChanged", "chainChanged"])
        XCTAssertEqual(approval.accounts, [
            "eip155:1:0x111",
            "eip155:8453:0x222",
            "eip155:137:0x333"
        ])
    }

    func testBuildsEVMApprovalForChainSpecificNamespaceKey() throws {
        let approval = try WalletConnectEVMNamespaceAdapter().buildApproval(
            requiredNamespaces: [
                WalletConnectNamespaceRequest(
                    namespace: "eip155:1",
                    chains: [],
                    methods: ["personal_sign"],
                    events: ["accountsChanged"]
                )
            ],
            optionalNamespaces: [],
            accounts: [WalletConnectEVMAccount(chainReference: "eip155:1", address: "0x111")]
        )

        XCTAssertEqual(approval.chains, ["eip155:1"])
        XCTAssertEqual(approval.accounts, ["eip155:1:0x111"])
    }

    func testBuildsEVMApprovalForChainlessNamespaceFromAvailableAccounts() throws {
        let approval = try WalletConnectEVMNamespaceAdapter().buildApproval(
            requiredNamespaces: [
                WalletConnectNamespaceRequest(
                    namespace: "eip155",
                    chains: [],
                    methods: ["personal_sign"],
                    events: ["accountsChanged"]
                )
            ],
            optionalNamespaces: [],
            accounts: [
                WalletConnectEVMAccount(chainReference: "eip155:1", address: "0x111"),
                WalletConnectEVMAccount(chainReference: "eip155:8453", address: "0x222")
            ]
        )

        XCTAssertEqual(approval.chains, ["eip155:1", "eip155:8453"])
        XCTAssertEqual(approval.accounts, ["eip155:1:0x111", "eip155:8453:0x222"])
    }

    func testBuildsEVMApprovalForOptionalChainlessNamespaceFromAvailableAccounts() throws {
        let approval = try WalletConnectEVMNamespaceAdapter().buildApproval(
            requiredNamespaces: [],
            optionalNamespaces: [
                WalletConnectNamespaceRequest(
                    namespace: "eip155",
                    chains: [],
                    methods: ["personal_sign"],
                    events: ["accountsChanged"]
                )
            ],
            accounts: [
                WalletConnectEVMAccount(chainReference: "eip155:1", address: "0x111"),
                WalletConnectEVMAccount(chainReference: "eip155:8453", address: "0x222")
            ]
        )

        XCTAssertEqual(approval.chains, ["eip155:1", "eip155:8453"])
        XCTAssertEqual(approval.accounts, ["eip155:1:0x111", "eip155:8453:0x222"])
    }

    func testRejectsUnsupportedRequiredNamespace() {
        XCTAssertThrowsError(try WalletConnectEVMNamespaceAdapter().buildApproval(
            requiredNamespaces: [
                WalletConnectNamespaceRequest(
                    namespace: "solana",
                    chains: ["solana:mainnet"],
                    methods: ["solana_signMessage"],
                    events: []
                )
            ],
            optionalNamespaces: [],
            accounts: [WalletConnectEVMAccount(chainReference: "eip155:1", address: "0x111")]
        )) { error in
            XCTAssertEqual(
                error as? WalletConnectNamespaceApprovalError,
                .unsupportedRequiredNamespace("solana")
            )
        }
    }

    func testRejectsMissingRequiredChainAccount() {
        XCTAssertThrowsError(try WalletConnectEVMNamespaceAdapter().buildApproval(
            requiredNamespaces: [
                WalletConnectNamespaceRequest(
                    namespace: "eip155",
                    chains: ["eip155:1", "eip155:10"],
                    methods: ["personal_sign"],
                    events: ["accountsChanged"]
                )
            ],
            optionalNamespaces: [],
            accounts: [WalletConnectEVMAccount(chainReference: "eip155:1", address: "0x111")]
        )) { error in
            XCTAssertEqual(
                error as? WalletConnectNamespaceApprovalError,
                .missingRequiredChain("eip155:10")
            )
        }
    }
}
