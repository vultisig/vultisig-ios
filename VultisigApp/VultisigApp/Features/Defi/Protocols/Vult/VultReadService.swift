//
//  VultReadService.swift
//  VultisigApp
//

import Foundation
import OSLog
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "vult-read-service")

/// One on-chain unstake request, as returned by `getUnstakeRequest(requestId)`.
/// `owner == 0` / `amount == 0` means the request was already settled or cancelled
/// (and should be pruned from local persistence).
struct VultUnstakeRequest: Equatable {
    let owner: String
    /// Unix maturity timestamp (seconds). Cooldown ends at this instant.
    let maturity: BigInt
    /// Escrowed amount in base units (18 dp), restored 1:1 to VULT on claim.
    let amount: BigInt

    var isEmpty: Bool {
        amount == .zero || owner == VultUnstakeRequest.zeroAddress
    }

    static let zeroAddress = "0x0000000000000000000000000000000000000000"
}

/// A decoded `UnstakeRequested` log captured from our own `requestUnstake` tx
/// receipt — the only way iOS (no `eth_getLogs`) learns the `requestId` of a
/// pending request.
struct VultUnstakeRequestedLog: Equatable {
    let requestId: BigInt
    let amount: BigInt
    /// Unix maturity timestamp (seconds).
    let maturity: BigInt
}

/// On-chain read layer for the sVULT staking wrapper. Builds read calldata,
/// decodes ABI-encoded `eth_call` return data, and decodes the `UnstakeRequested`
/// receipt log. All decoders fail closed: a malformed/empty payload throws rather
/// than coercing to a zero state.
struct VultReadService {
    static let shared = VultReadService()

    private let chain: Chain
    private let stakedVult: String

    init(
        chain: Chain = VultConstants.chain,
        stakedVult: String = VultConstants.stakedVult
    ) {
        self.chain = chain
        self.stakedVult = stakedVult
    }

    // MARK: - Reads

    /// Active staked sVULT for `user` (1:1 VULT), via `balanceOf(address)`.
    func balanceOf(user: String) async throws -> BigInt {
        let service = try EvmService.getService(forChain: chain)
        return try await service.fetchERC20TokenBalance(contractAddress: stakedVult, walletAddress: user)
    }

    /// Current unstake cooldown in seconds (`cooldownDuration()`). 0 ⇒ instant
    /// withdraw is permitted by the contract.
    func cooldownDuration() async throws -> BigInt {
        let service = try EvmService.getService(forChain: chain)
        let data = "0x" + VultConstants.Selector.cooldownDuration
        return try await callUInt(to: stakedVult, data: data, service: service)
    }

    /// `getUnstakeRequest(requestId)` → `(owner, maturity, amount)`.
    func getUnstakeRequest(requestId: BigInt) async throws -> VultUnstakeRequest {
        let service = try EvmService.getService(forChain: chain)
        let data = "0x" + VultConstants.Selector.getUnstakeRequest + pad(uint: requestId)
        let raw = try await service.callContract(to: stakedVult, data: data)
        return try Self.decodeUnstakeRequest(raw)
    }

    /// `isClaimable(requestId)` → bool. A non-zero final word is `true`.
    func isClaimable(requestId: BigInt) async throws -> Bool {
        let service = try EvmService.getService(forChain: chain)
        let data = "0x" + VultConstants.Selector.isClaimable + pad(uint: requestId)
        let value = try await callUInt(to: stakedVult, data: data, service: service)
        return value != .zero
    }

    /// `underlying()` → the staked ERC-20 address. Used to confirm the VULT
    /// constant at runtime rather than trusting it blindly.
    func underlying() async throws -> String {
        let service = try EvmService.getService(forChain: chain)
        let data = "0x" + VultConstants.Selector.underlying
        let raw = try await service.callContract(to: stakedVult, data: data)
        return try Self.decodeAddress(raw)
    }

    // MARK: - Private

    private func callUInt(to: String, data: String, service: EvmService) async throws -> BigInt {
        let raw = try await service.callContract(to: to, data: data)
        return try Self.decodeUInt(raw)
    }

    private func pad(uint value: BigInt) -> String {
        String(value, radix: 16).paddingLeft(toLength: 64, withPad: "0")
    }

    // MARK: - Decoding (fail closed)

    /// Decodes a single ABI uint256 word. An empty (reverted) or unparseable
    /// payload throws rather than coercing to `0`.
    static func decodeUInt(_ raw: String) throws -> BigInt {
        let hex = raw.stripHexPrefix()
        guard !hex.isEmpty, let value = BigInt(hex, radix: 16) else {
            throw VultServiceError.readError("Malformed uint256 read payload")
        }
        return value
    }

    /// Decodes the last 20 bytes of the first ABI word as an address.
    static func decodeAddress(_ raw: String) throws -> String {
        let words = try abiWords(raw)
        guard let first = words.first else {
            throw VultServiceError.readError("Empty address read payload")
        }
        let hex = String(first, radix: 16).paddingLeft(toLength: 40, withPad: "0")
        return "0x" + String(hex.suffix(40))
    }

    /// Decodes the `getUnstakeRequest` 3-word tuple `(owner, maturity, amount)`.
    static func decodeUnstakeRequest(_ raw: String) throws -> VultUnstakeRequest {
        let words = try abiWords(raw)
        guard words.count >= 3 else {
            throw VultServiceError.readError("Unexpected getUnstakeRequest response")
        }
        let ownerHex = String(words[0], radix: 16).paddingLeft(toLength: 40, withPad: "0")
        return VultUnstakeRequest(
            owner: "0x" + String(ownerHex.suffix(40)),
            maturity: words[1],
            amount: words[2]
        )
    }

    /// Splits raw ABI return data into 32-byte uint256 words. Fails closed on a
    /// length that isn't a whole number of words or a non-hex word.
    static func abiWords(_ raw: String) throws -> [BigInt] {
        let hex = raw.stripHexPrefix()
        guard !hex.isEmpty, hex.count % 64 == 0 else {
            throw VultServiceError.readError("Misaligned ABI read payload")
        }
        var words: [BigInt] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 64)
            let word = String(hex[index..<next])
            guard let value = BigInt(word, radix: 16) else {
                throw VultServiceError.readError("Malformed ABI word in read payload")
            }
            words.append(value)
            index = next
        }
        return words
    }

    // MARK: - Receipt log decode (requestId capture, Decision 5)

    /// Finds and decodes the `UnstakeRequested` log in an `eth_getTransactionReceipt`
    /// result. Matches the log by the sVULT contract address and the event topic0;
    /// `requestId` is the indexed `topics[2]`, and `amount` / `maturity` are the
    /// first two data words.
    ///
    /// Returns `nil` (never crashes) if the receipt has no matching log — the
    /// caller treats that as "couldn't read the request id" and persists a
    /// needs-reconcile marker rather than dropping a real pending request.
    func decodeUnstakeRequestedLog(receipt: [String: Any]) -> VultUnstakeRequestedLog? {
        Self.decodeUnstakeRequestedLog(receipt: receipt, contract: stakedVult)
    }

    static func decodeUnstakeRequestedLog(receipt: [String: Any], contract: String) -> VultUnstakeRequestedLog? {
        guard let logs = receipt["logs"] as? [[String: Any]] else {
            logger.warning("Receipt has no logs array; cannot capture requestId")
            return nil
        }
        let topic0 = VultConstants.EventTopic.unstakeRequested.lowercased()
        let target = contract.lowercased()

        for log in logs {
            guard
                let address = (log["address"] as? String)?.lowercased(),
                address == target,
                let topics = log["topics"] as? [String],
                topics.count >= 3,
                topics[0].lowercased() == topic0
            else { continue }

            guard let requestId = BigInt(topics[2].stripHexPrefix(), radix: 16) else {
                logger.error("UnstakeRequested log has unparseable requestId topic")
                return nil
            }

            let dataWords = (try? abiWords(log["data"] as? String ?? "")) ?? []
            guard dataWords.count >= 2 else {
                logger.error("UnstakeRequested log data has fewer than 2 words")
                return nil
            }

            return VultUnstakeRequestedLog(
                requestId: requestId,
                amount: dataWords[0],
                maturity: dataWords[1]
            )
        }

        logger.warning("No UnstakeRequested log found in receipt for \(target)")
        return nil
    }
}
