//
//  ERC20ApprovalResolverTests.swift
//  VultisigAppTests
//
//  The initiator's approval decision: the allowance read, the approve
//  simulation, and how their answers map to no approve, one approve, or a
//  reset first. Every RPC is scripted, nothing reaches a node.
//

import BigInt
import XCTest
@testable import VultisigApp

final class ERC20ApprovalResolverTests: XCTestCase {

    private static let usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
    private static let owner = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    private static let spender = "0x111111125421cA6dc452d289314280a0f8842A65"
    private static let amount = BigInt(2_000_000)

    private static let allowanceCalldata = "0xdd62ed3e"
        + "000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045"
        + "000000000000000000000000111111125421ca6dc452d289314280a0f8842a65"
    private static let approveCalldata = "0x095ea7b3"
        + "000000000000000000000000111111125421ca6dc452d289314280a0f8842a65"
        + "00000000000000000000000000000000000000000000000000000000001e8480"

    // MARK: - Requirement

    func testZeroAllowanceIsASingleApproveWithoutProbe() async throws {
        let rpc = ScriptedEVMCalls([.success(.returned(data: Self.word(0)))])

        let requirement = try await resolver(rpc).requirement(for: Self.query)

        XCTAssertEqual(requirement, .approve)
        XCTAssertEqual(rpc.calls, [Self.allowanceCall])
    }

    func testAllowanceEqualToAmountNeedsNoApprove() async throws {
        let rpc = ScriptedEVMCalls([.success(.returned(data: Self.word(Self.amount)))])

        let requirement = try await resolver(rpc).requirement(for: Self.query)

        XCTAssertEqual(requirement, .notRequired)
        XCTAssertEqual(rpc.calls.count, 1)
    }

    func testUnlimitedAllowanceNeedsNoApprove() async throws {
        let rpc = ScriptedEVMCalls([.success(.returned(data: "0x" + String(repeating: "f", count: 64)))])

        let requirement = try await resolver(rpc).requirement(for: Self.query)

        XCTAssertEqual(requirement, .notRequired)
        XCTAssertEqual(rpc.calls.count, 1)
    }

    /// USDT's guard is a bare `revert()`: no data, generic -32000.
    func testPartialAllowanceWithRevertingApproveResetsFirst() async throws {
        let rpc = ScriptedEVMCalls([
            .success(.returned(data: Self.word(1_000_000))),
            .success(.failed(code: -32000, message: "execution reverted"))
        ])

        let requirement = try await resolver(rpc).requirement(for: Self.query)

        XCTAssertEqual(requirement, .resetThenApprove)
        XCTAssertEqual(rpc.calls, [Self.allowanceCall, Self.probeCall])
    }

    func testPartialAllowanceWithRevertCarryingDataResetsFirst() async throws {
        let rpc = ScriptedEVMCalls([
            .success(.returned(data: Self.word(1_000_000))),
            .success(.failed(code: 3, message: "execution reverted: approve from non-zero"))
        ])

        let requirement = try await resolver(rpc).requirement(for: Self.query)

        XCTAssertEqual(requirement, .resetThenApprove)
    }

    func testPartialAllowanceWithSucceedingApproveIsAPlainApprove() async throws {
        let rpc = ScriptedEVMCalls([
            .success(.returned(data: Self.word(1_000_000))),
            .success(.returned(data: Self.word(1)))
        ])

        let requirement = try await resolver(rpc).requirement(for: Self.query)

        XCTAssertEqual(requirement, .approve)
        XCTAssertEqual(rpc.calls, [Self.allowanceCall, Self.probeCall])
    }

    /// A token whose approve returns nothing, and does not revert, is a plain approve.
    func testApproveThatReturnsNoDataIsAPlainApprove() async throws {
        let rpc = ScriptedEVMCalls([
            .success(.returned(data: Self.word(1_000_000))),
            .success(.returned(data: "0x"))
        ])

        let requirement = try await resolver(rpc).requirement(for: Self.query)

        XCTAssertEqual(requirement, .approve)
    }

    // MARK: - Failures propagate

    func testProbeNodeErrorPropagates() async {
        let rpc = ScriptedEVMCalls([
            .success(.returned(data: Self.word(1_000_000))),
            .success(.failed(code: -32000, message: "header not found"))
        ])

        await assertThrowsRPCError(code: -32000, message: "header not found") {
            _ = try await self.resolver(rpc).requirement(for: Self.query)
        }
    }

    func testProbeTransportErrorPropagates() async {
        let rpc = ScriptedEVMCalls([
            .success(.returned(data: Self.word(1_000_000))),
            .failure(URLError(.timedOut))
        ])

        do {
            _ = try await resolver(rpc).requirement(for: Self.query)
            XCTFail("Expected the transport error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }
    }

    func testMalformedProbeResultPropagates() async {
        let rpc = ScriptedEVMCalls([
            .success(.returned(data: Self.word(1_000_000))),
            .success(.returned(data: "0xabc"))
        ])

        await assertThrowsRPCError(code: 500) {
            _ = try await self.resolver(rpc).requirement(for: Self.query)
        }
    }

    func testAllowanceNodeErrorPropagatesWithoutProbe() async {
        let rpc = ScriptedEVMCalls([.success(.failed(code: -32005, message: "rate limit exceeded"))])

        await assertThrowsRPCError(code: -32005, message: "rate limit exceeded") {
            _ = try await self.resolver(rpc).requirement(for: Self.query)
        }
        XCTAssertEqual(rpc.calls.count, 1)
    }

    /// A revert on the read is still a failed read, never "allowance 0".
    func testAllowanceRevertPropagates() async {
        let rpc = ScriptedEVMCalls([.success(.failed(code: -32000, message: "execution reverted"))])

        await assertThrowsRPCError(code: -32000, message: "execution reverted") {
            _ = try await self.resolver(rpc).requirement(for: Self.query)
        }
    }

    func testAllowanceTransportErrorPropagates() async {
        let rpc = ScriptedEVMCalls([.failure(URLError(.notConnectedToInternet))])

        do {
            _ = try await resolver(rpc).requirement(for: Self.query)
            XCTFail("Expected the transport error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }
    }

    /// `0x` is what an address with no code answers. It is not a zero allowance.
    func testEmptyAllowanceResultPropagates() async {
        let rpc = ScriptedEVMCalls([.success(.returned(data: "0x"))])

        await assertThrowsRPCError(code: 500) {
            _ = try await self.resolver(rpc).requirement(for: Self.query)
        }
    }

    func testAllowanceResultLongerThanOneWordPropagates() async {
        let rpc = ScriptedEVMCalls([.success(.returned(data: Self.word(0) + String(repeating: "0", count: 64)))])

        await assertThrowsRPCError(code: 500) {
            _ = try await self.resolver(rpc).requirement(for: Self.query)
        }
    }

    func testInvalidOwnerAddressFailsBeforeAnyCall() async {
        let rpc = ScriptedEVMCalls([])
        let query = ERC20ApprovalQuery(chain: .ethereum, token: Self.usdt, owner: "not-an-address", spender: Self.spender, amount: Self.amount)

        do {
            _ = try await resolver(rpc).requirement(for: query)
            XCTFail("Expected an invalid-address error")
        } catch {
            XCTAssertTrue(rpc.calls.isEmpty)
        }
    }

    // MARK: - Calldata

    func testAllowanceCalldataEncodesOwnerThenSpender() throws {
        XCTAssertEqual(
            try EthereumFunction.allowanceErc20Encoder(owner: Self.owner, spender: Self.spender),
            Self.allowanceCalldata
        )
    }

    func testApproveProbeCalldataEncodesSpenderAndAmount() throws {
        XCTAssertEqual(
            try EthereumFunction.approvalErc20Encoder(address: Self.spender, amount: Self.amount),
            Self.approveCalldata
        )
    }

    // MARK: - Payload

    func testRequirementMapsToTheApprovePayload() {
        XCTAssertNil(ERC20ApprovalRequirement.notRequired.approvePayload(amount: Self.amount, spender: Self.spender))
        XCTAssertEqual(
            ERC20ApprovalRequirement.approve.approvePayload(amount: Self.amount, spender: Self.spender),
            ERC20ApprovePayload(amount: Self.amount, spender: Self.spender)
        )
        XCTAssertEqual(
            ERC20ApprovalRequirement.resetThenApprove.approvePayload(amount: Self.amount, spender: Self.spender),
            ERC20ApprovePayload(amount: Self.amount, spender: Self.spender, resetAllowanceFirst: true)
        )
    }

    // MARK: - Decision

    func testDecisionKeepsTheSpendItWasReadFor() async throws {
        let rpc = ScriptedEVMCalls([.success(.returned(data: Self.word(0)))])

        let decision = try await resolver(rpc).decision(for: Self.query)

        XCTAssertEqual(decision, ERC20ApprovalDecision(query: Self.query, requirement: .approve))
    }

    func testOnlyNotRequiredSignsNoApprove() {
        XCTAssertFalse(ERC20ApprovalDecision(query: Self.query, requirement: .notRequired).signsApprove)
        XCTAssertTrue(ERC20ApprovalDecision(query: Self.query, requirement: .approve).signsApprove)
        XCTAssertTrue(ERC20ApprovalDecision(query: Self.query, requirement: .resetThenApprove).signsApprove)
    }

    func testDecisionForTheSpendBeingSignedMapsToItsPayload() throws {
        let decision = ERC20ApprovalDecision(query: Self.query, requirement: .resetThenApprove)

        XCTAssertEqual(
            try ERC20ApprovalDecision.approvePayload(signing: Self.query, decision: decision),
            ERC20ApprovePayload(amount: Self.amount, spender: Self.spender, resetAllowanceFirst: true)
        )
    }

    func testSpendWithoutAnApproveNeedsNoDecision() throws {
        XCTAssertNil(try ERC20ApprovalDecision.approvePayload(signing: nil, decision: nil))
    }

    func testSpendWithoutADecisionIsRefused() {
        XCTAssertThrowsError(try ERC20ApprovalDecision.approvePayload(signing: Self.query, decision: nil)) {
            XCTAssertEqual($0 as? ERC20ApprovalDecisionError, .stale)
        }
    }

    func testDecisionForAnyOtherSpendIsRefused() {
        let decision = ERC20ApprovalDecision(query: Self.query, requirement: .notRequired)
        let others = [
            ERC20ApprovalQuery(chain: .ethereum, token: Self.usdt, owner: Self.owner, spender: Self.owner, amount: Self.amount),
            ERC20ApprovalQuery(chain: .ethereum, token: Self.usdt, owner: Self.owner, spender: Self.spender, amount: Self.amount + 1),
            ERC20ApprovalQuery(chain: .ethereum, token: Self.spender, owner: Self.owner, spender: Self.spender, amount: Self.amount),
            ERC20ApprovalQuery(chain: .ethereum, token: Self.usdt, owner: Self.spender, spender: Self.spender, amount: Self.amount),
            ERC20ApprovalQuery(chain: .arbitrum, token: Self.usdt, owner: Self.owner, spender: Self.spender, amount: Self.amount)
        ]

        for other in others {
            XCTAssertThrowsError(try ERC20ApprovalDecision.approvePayload(signing: other, decision: decision), "\(other)")
        }
    }

    // MARK: - Helpers

    private static let query = ERC20ApprovalQuery(chain: .ethereum, token: usdt, owner: owner, spender: spender, amount: amount)
    private static let allowanceCall = ScriptedEVMCalls.Call(chain: .ethereum, from: nil, to: usdt, data: allowanceCalldata)
    private static let probeCall = ScriptedEVMCalls.Call(chain: .ethereum, from: owner, to: usdt, data: approveCalldata)

    private func resolver(_ rpc: ScriptedEVMCalls) -> ERC20ApprovalResolver {
        ERC20ApprovalResolver(rpc: rpc)
    }

    private static func word(_ value: BigInt) -> String {
        let hex = String(value, radix: 16)
        return "0x" + String(repeating: "0", count: 64 - hex.count) + hex
    }

    private func assertThrowsRPCError(
        code: Int,
        message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected an RPC error", file: file, line: line)
        } catch let RpcServiceError.rpcError(thrownCode, thrownMessage) {
            XCTAssertEqual(thrownCode, code, file: file, line: line)
            if let message {
                XCTAssertEqual(thrownMessage, message, file: file, line: line)
            }
        } catch {
            XCTFail("Expected RpcServiceError.rpcError, got \(error)", file: file, line: line)
        }
    }
}

/// Answers each `eth_call` with the next scripted reply and records what was asked.
private final class ScriptedEVMCalls: EVMCallPerforming {
    struct Call: Equatable {
        let chain: Chain
        let from: String?
        let to: String
        let data: String
    }

    private(set) var calls: [Call] = []
    private var replies: [Result<EVMCallOutcome, Error>]

    init(_ replies: [Result<EVMCallOutcome, Error>]) {
        self.replies = replies
    }

    // swiftlint:disable:next async_without_await
    func ethCall(chain: Chain, from: String?, to: String, data: String) async throws -> EVMCallOutcome {
        calls.append(Call(chain: chain, from: from, to: to, data: data))
        guard !replies.isEmpty else {
            XCTFail("Unexpected eth_call to \(to)")
            throw URLError(.unknown)
        }
        return try replies.removeFirst().get()
    }
}
