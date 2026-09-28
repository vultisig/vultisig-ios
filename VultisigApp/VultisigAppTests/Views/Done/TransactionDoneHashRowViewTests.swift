//
//  TransactionDoneHashRowViewTests.swift
//  VultisigAppTests
//
//  `TransactionDoneHashRowView` is the one shared hash row for every
//  "done" surface — Send Done and Swap Done's main/approval hashes —
//  mirroring Android's single `TxDetails` composable. These tests pin
//  its two Android-parity rules that don't hold by default: the
//  explorer button disappears (rather than rendering dead) when the
//  chain has no explorer, and copy falls back to the raw hash instead
//  of copying nothing.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TransactionDoneHashRowViewTests: XCTestCase {

    func testExplorerLinkHiddenWhenLinkEmpty() {
        let row = TransactionDoneHashRowView(hash: "abc123", explorerLink: "", showCopy: true)
        XCTAssertFalse(row.hasExplorerLink)
    }

    func testExplorerLinkShownWhenLinkPresent() {
        let row = TransactionDoneHashRowView(
            hash: "abc123",
            explorerLink: "https://etherscan.io/tx/abc123",
            showCopy: true
        )
        XCTAssertTrue(row.hasExplorerLink)
    }

    func testCopyFallsBackToRawHashWhenLinkEmpty() {
        let row = TransactionDoneHashRowView(hash: "abc123", explorerLink: "", showCopy: true)
        XCTAssertEqual(row.clipboardValue, "abc123")
    }

    func testCopyUsesExplorerLinkWhenPresent() {
        let row = TransactionDoneHashRowView(
            hash: "abc123",
            explorerLink: "https://etherscan.io/tx/abc123",
            showCopy: true
        )
        XCTAssertEqual(row.clipboardValue, "https://etherscan.io/tx/abc123")
    }

    /// Send Done doesn't pass a title — the row keeps its original label.
    func testTitleDefaultsToTransactionHashForSendDone() {
        let row = TransactionDoneHashRowView(hash: "abc123", explorerLink: "", showCopy: true)
        XCTAssertEqual(row.title, "transactionHash")
    }

    /// Swap Done reuses the same row for its main and approval hash cells,
    /// overriding only the title — no parallel swap-only view or icon.
    func testSwapDoneOverridesTitlePerRow() {
        let mainRow = TransactionDoneHashRowView(title: "swapTXHash", hash: "abc123", explorerLink: "", showCopy: true)
        let approvalRow = TransactionDoneHashRowView(
            title: "approvalTXHash",
            hash: "def456",
            explorerLink: "",
            showCopy: true
        )
        XCTAssertEqual(mainRow.title, "swapTXHash")
        XCTAssertEqual(approvalRow.title, "approvalTXHash")
    }
}
