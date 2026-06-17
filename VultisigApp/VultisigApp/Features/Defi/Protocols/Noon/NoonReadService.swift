//
//  NoonReadService.swift
//  VultisigApp
//

import Foundation
import BigInt

/// Decoded snapshot of the user's position in the Noon vault, derived from the
/// on-chain `getState`, `balanceOf`, and `convertToAssets` reads.
struct NoonVaultState: Equatable {
    let maxWithdraw: BigInt
    let redeemShares: BigInt
    let pendingRedeemRequest: BigInt
}

struct NoonVaultPosition: Equatable {
    let shareBalance: BigInt
    let currentAssets: BigInt
    let claimableAssets: BigInt
    let claimableRedeemShares: BigInt
    let pendingRedeemShares: BigInt
    let redemptionState: NoonRedemptionState
}

/// Read model lifecycle for an ERC-7540 redemption. `none` is the domain term
/// for "no redemption in flight" and is persisted as the row's raw value.
enum NoonRedemptionState: String, Equatable {
    // swiftlint:disable:next discouraged_none_name
    case none
    case pending
    case claimable

    /// Derives the state from the relevant on-chain reads. Claimable assets (or
    /// settled redeem shares) win over a still-pending request.
    static func derive(claimableAssets: BigInt, claimableRedeemShares: BigInt, pendingRedeemShares: BigInt) -> NoonRedemptionState {
        if claimableAssets > 0 || claimableRedeemShares > 0 {
            return .claimable
        }
        if pendingRedeemShares > 0 {
            return .pending
        }
        return .none
    }
}

/// On-chain read layer for the Noon ERC-7540 vault. Builds read calldata and
/// decodes the ABI-encoded return data from `eth_call`.
struct NoonReadService {
    static let shared = NoonReadService()

    private let chain: Chain
    private let vault: String
    private let usdc: String

    private enum Selector {
        static let convertToAssets = "07a2d13a"  // convertToAssets(uint256)
        static let maxWithdraw = "ce96cb77"       // maxWithdraw(address)
        static let getState = "1bab58f5"          // getState(address)
    }

    init(
        chain: Chain = NoonConstants.chain,
        vaultAddress: String = NoonConstants.vaultAddress,
        usdcAddress: String = NoonConstants.usdcMainnet
    ) {
        self.chain = chain
        self.vault = vaultAddress
        self.usdc = usdcAddress
    }

    // MARK: - Position

    /// Composes the user's full position from `getState` + `balanceOf` +
    /// `convertToAssets`, deriving the redemption read state.
    func fetchPosition(user: String) async throws -> NoonVaultPosition {
        let service = try EvmService.getService(forChain: chain)

        async let stateTask = fetchState(user: user, service: service)
        async let shareBalanceTask = service.fetchERC20TokenBalance(contractAddress: vault, walletAddress: user)

        let state = try await stateTask
        let shareBalance = try await shareBalanceTask
        let currentAssets = try await convertToAssets(shares: shareBalance, service: service)

        let redemptionState = NoonRedemptionState.derive(
            claimableAssets: state.maxWithdraw,
            claimableRedeemShares: state.redeemShares,
            pendingRedeemShares: state.pendingRedeemRequest
        )

        return NoonVaultPosition(
            shareBalance: shareBalance,
            currentAssets: currentAssets,
            claimableAssets: state.maxWithdraw,
            claimableRedeemShares: state.redeemShares,
            pendingRedeemShares: state.pendingRedeemRequest,
            redemptionState: redemptionState
        )
    }

    // MARK: - Reads

    func maxWithdraw(user: String) async throws -> BigInt {
        let service = try EvmService.getService(forChain: chain)
        let data = "0x" + Selector.maxWithdraw + pad(address: user)
        return try await callUInt(to: vault, data: data, service: service)
    }

    /// The owner's vault share balance (naccUSDC) — `balanceOf(owner)` on the
    /// vault token. Used to denominate a redeem request in shares.
    func shareBalance(owner: String) async throws -> BigInt {
        let service = try EvmService.getService(forChain: chain)
        return try await service.fetchERC20TokenBalance(contractAddress: vault, walletAddress: owner)
    }

    func allowance(owner: String) async throws -> BigInt {
        let service = try EvmService.getService(forChain: chain)
        return try await service.fetchAllowance(contractAddress: usdc, owner: owner, spender: vault)
    }

    func convertToAssets(shares: BigInt) async throws -> BigInt {
        let service = try EvmService.getService(forChain: chain)
        return try await convertToAssets(shares: shares, service: service)
    }

    // MARK: - Private

    private func fetchState(user: String, service: EvmService) async throws -> NoonVaultState {
        let data = "0x" + Selector.getState + pad(address: user)
        let raw = try await service.callContract(to: vault, data: data)
        return try Self.decodeState(raw)
    }

    private func convertToAssets(shares: BigInt, service: EvmService) async throws -> BigInt {
        guard shares > 0 else { return .zero }
        let data = "0x" + Selector.convertToAssets + pad(uint: shares)
        return try await callUInt(to: vault, data: data, service: service)
    }

    private func callUInt(to: String, data: String, service: EvmService) async throws -> BigInt {
        let raw = try await service.callContract(to: to, data: data)
        return try Self.decodeUInt(raw)
    }

    // MARK: - Encoding / decoding helpers

    private func pad(address: String) -> String {
        String(address.stripHexPrefix().lowercased()).paddingLeft(toLength: 64, withPad: "0")
    }

    private func pad(uint value: BigInt) -> String {
        String(value, radix: 16).paddingLeft(toLength: 64, withPad: "0")
    }

    /// Decodes a single ABI uint256 word from a `0x`-prefixed return string.
    /// Fails closed: an empty (reverted/empty `eth_call`) or unparseable payload
    /// throws rather than coercing to `0`, so a bad read can't masquerade as a
    /// valid zero state driving redemption / minimum logic.
    static func decodeUInt(_ raw: String) throws -> BigInt {
        let hex = raw.stripHexPrefix()
        guard !hex.isEmpty, let value = BigInt(hex, radix: 16) else {
            throw NoonServiceError.readError("Malformed uint256 read payload")
        }
        return value
    }

    /// Decodes the `getState` tuple. The struct is returned head-only (10 static
    /// uint256 words); `maxWithdraw` is word 1, `redeemShares` is word 3, and
    /// `pendingRedeemRequest` is the final (10th) word.
    static func decodeState(_ raw: String) throws -> NoonVaultState {
        let words = try abiWords(raw)
        guard words.count >= 10 else {
            throw NoonServiceError.readError("Unexpected getState response")
        }
        return NoonVaultState(
            maxWithdraw: words[1],
            redeemShares: words[3],
            pendingRedeemRequest: words[9]
        )
    }

    /// Splits raw ABI return data into 32-byte uint256 words. Fails closed: a
    /// length that isn't a whole number of 32-byte words, or a word that doesn't
    /// parse as hex, throws rather than yielding `[]` / `0`-padded words, so a
    /// truncated or garbage `eth_call` payload can't decode to a bogus state.
    static func abiWords(_ raw: String) throws -> [BigInt] {
        let hex = raw.stripHexPrefix()
        guard !hex.isEmpty, hex.count % 64 == 0 else {
            throw NoonServiceError.readError("Misaligned ABI read payload")
        }
        var words: [BigInt] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 64)
            let word = String(hex[index..<next])
            guard let value = BigInt(word, radix: 16) else {
                throw NoonServiceError.readError("Malformed ABI word in read payload")
            }
            words.append(value)
            index = next
        }
        return words
    }
}
