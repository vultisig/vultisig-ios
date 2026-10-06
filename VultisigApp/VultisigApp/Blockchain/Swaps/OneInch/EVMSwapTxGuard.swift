//
//  EVMSwapTxGuard.swift
//  VultisigApp
//

import Foundation
import BigInt

enum EVMSwapTxGuardError: Error, LocalizedError, Equatable {
    case malformedValue(String)
    case malformedAmount(String)
    case coinMismatch
    case unrecognizedProvider(String)
    case unknownRouter(router: String, provider: String, chain: String)
    case valueExceedsQuotedAmount(value: String, quoted: String)
    case valueFromTokenSource(value: String)
    case swapKitDepositRefused(String)

    var errorDescription: String? {
        switch self {
        case .malformedValue(let value):
            return "EVM swap tx.value '\(value)' is not a non-negative integer"
        case .malformedAmount(let amount):
            return "EVM swap fromAmount '\(amount)' is not a non-negative integer"
        case .coinMismatch:
            return "EVM swap payload source coin does not match the coin being signed"
        case .unrecognizedProvider(let provider):
            return "EVM swap from unrecognized provider '\(provider)'"
        case .unknownRouter(let router, let provider, let chain):
            return "EVM swap router \(router) is not a known \(provider) router on \(chain)"
        case .valueExceedsQuotedAmount(let value, let quoted):
            return "EVM swap sends \(value) native units, more than the quoted \(quoted)"
        case .valueFromTokenSource(let value):
            return "EVM swap from an ERC-20 source must not send native value, got \(value)"
        case .swapKitDepositRefused(let reason):
            return "SwapKit ERC-20 deposit \(reason)"
        }
    }
}

/// Checks an EVM aggregator swap before it is signed. The co-signer rebuilds the
/// transaction from the relayed payload and its verify screen only shows the quoted
/// tokens and amounts, so `tx.to` and `tx.value` must be ones the quote implies
/// rather than whatever the provider response (or a compromised initiator) put there.
///
/// - `tx.to` must be the provider's router on that chain. SwapKit is exempt: its
///   entry contract is chosen per route, so there is no fixed address to pin.
///   A SwapKit `transfer` call or a SwapKit tx addressed to the sold token (an
///   ERC-20 deposit) must instead be exactly `transfer(recipient, fromAmount)`
///   on the sold token with no native value.
/// - A 1inch / Kyber swap (or a provider-less one aimed at their routers) cannot
///   send more native value than the quoted amount and sends none from an ERC-20
///   source. LI.FI and SwapKit are exempt: bridge routes add native messaging fees
///   on top of the quoted amount, so `tx.value` can legitimately exceed it.
///
/// Router addresses mirror vultisig-sdk's `knownAggregatorRouters.ts` and the
/// Android `EvmSwapTxGuard`; the three platforms must refuse the same payloads.
enum EVMSwapTxGuard {

    static func check(_ payload: GenericSwapPayload, signingCoin: Coin) throws {
        // Routing into the EVM signer is decided by the signing coin, so either side
        // being EVM puts the swap in scope; a payload coin on another chain must not
        // let the signing coin skip the checks.
        let chain = payload.fromCoin.chain
        guard chain.chainType == .EVM || signingCoin.chain.chainType == .EVM else { return }
        let tx = payload.quote.tx

        // The bounds below read the payload's coin, so it must be the coin the
        // signed transaction is built for. The approval leg is built from the
        // signing coin's contract, so the token must match, not just its kind.
        guard signingCoin.chain == chain,
              signingCoin.isNativeToken == payload.fromCoin.isNativeToken,
              signingCoin.contractAddress.lowercased() == payload.fromCoin.contractAddress.lowercased() else {
            throw EVMSwapTxGuardError.coinMismatch
        }

        guard let value = BigUInt(tx.value), value.bitWidth <= 256 else {
            throw EVMSwapTxGuardError.malformedValue(tx.value)
        }

        let rawProvider = payload.provider.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = SwapProviderId.from(rawValue: rawProvider)
        // SwapKit skips the router pin, so only its exact wire id earns that, as on the SDK.
        if provider == .swapkit, payload.provider != .swapkit {
            throw EVMSwapTxGuardError.unrecognizedProvider(payload.provider.rawValue)
        }
        let to = tx.to.lowercased()

        let routers: Set<String>?
        switch provider {
        case .swapkit:
            _ = try Self.swapKitDepositRecipient(of: payload)
            routers = nil
        case .oneInch, .kyberSwap, .lifi, .jupiter:
            routers = Self.routers(for: provider, chain: chain)
        case .unknown:
            guard rawProvider.isEmpty else {
                throw EVMSwapTxGuardError.unrecognizedProvider(rawProvider)
            }
            routers = Self.enforcedProviders.reduce(into: Set<String>()) {
                $0.formUnion(Self.routers(for: $1, chain: chain))
            }
        }
        if let routers, !routers.contains(to) {
            throw EVMSwapTxGuardError.unknownRouter(
                router: tx.to,
                provider: rawProvider.isEmpty ? "aggregator" : rawProvider,
                chain: chain.rawValue
            )
        }

        let boundsValue: Bool
        switch provider {
        case .oneInch, .kyberSwap:
            boundsValue = true
        case .unknown:
            boundsValue = Self.exactValueRouters(chain: chain).contains(to)
        case .lifi, .swapkit, .jupiter:
            boundsValue = false
        }
        guard boundsValue else { return }

        if payload.fromCoin.isNativeToken {
            guard payload.fromAmount.sign != .minus, value <= payload.fromAmount.magnitude else {
                throw EVMSwapTxGuardError.valueExceedsQuotedAmount(
                    value: String(value),
                    quoted: String(payload.fromAmount)
                )
            }
        } else if value != 0 {
            throw EVMSwapTxGuardError.valueFromTokenSource(value: String(value))
        }
    }

    /// The recipient of the SwapKit ERC-20 deposit `payload` signs, decoded from
    /// its calldata by `swapKitErc20DepositRecipient`; nil when it is not one.
    static func swapKitDepositRecipient(of payload: GenericSwapPayload) throws -> String? {
        guard payload.provider == .swapkit, payload.fromCoin.chain.chainType == .EVM else { return nil }
        let tx = payload.quote.tx
        guard let value = BigUInt(tx.value), value.bitWidth <= 256 else {
            throw EVMSwapTxGuardError.malformedValue(tx.value)
        }
        return try swapKitErc20DepositRecipient(
            to: tx.to,
            data: tx.data,
            value: BigInt(value),
            sourceToken: payload.fromCoin.contractAddress,
            amount: payload.fromAmount
        )
    }

    /// Refuses a SwapKit ERC-20 deposit whose recipient lacks a Benign Blockaid
    /// verdict. Warning, Malicious, an unsupported chain and a failed scan all
    /// refuse, as vultisig-sdk's `assertSwapKitAddressReputation` does.
    static func screenSwapKitDepositRecipient(
        _ keysignPayload: KeysignPayload,
        blockaid: BlockaidRpcClientProtocol = BlockaidRpcClient(httpClient: HTTPClient())
    ) async throws {
        guard case .generic(let swap) = keysignPayload.swapPayload,
              let recipient = try swapKitDepositRecipient(of: swap) else { return }
        let chain = swap.fromCoin.chain
        let verdict: BlockaidAddressScanResponseJson
        do {
            verdict = try await blockaid.scanEVMAddress(chain: chain, address: recipient)
        } catch {
            try Task.checkCancellation()
            throw EVMSwapTxGuardError.swapKitDepositRefused(
                "recipient \(recipient) could not be screened on \(chain.name): \(error.localizedDescription)"
            )
        }
        guard verdict.resultType == "Benign" else {
            let features = verdict.features ?? []
            let detail = features.isEmpty ? "" : " (\(features.joined(separator: ", ")))"
            throw EVMSwapTxGuardError.swapKitDepositRefused(
                "recipient \(recipient) received a \(verdict.resultType) Blockaid verdict on \(chain.name)\(detail)"
            )
        }
    }

    /// A SwapKit deposit route (NEAR Intents `simpleTransfer`) that sells an
    /// ERC-20 calls the token itself with `transfer(recipient, amount)`. Returns
    /// the lowercase recipient when the call is exactly that: addressed to the
    /// sold token, no native value, exactly `transfer(address,uint256)`, the sold
    /// amount. Returns nil when it is neither addressed to the sold token nor a
    /// `transfer` call. Anything else that is (another token, native value, other
    /// calldata, another amount) throws. Mirrors vultisig-sdk's
    /// `getSwapKitErc20DepositRecipient`.
    static func swapKitErc20DepositRecipient(
        to: String,
        data: String,
        value: BigInt,
        sourceToken: String,
        amount: BigInt
    ) throws -> String? {
        let calldata = data.lowercased().stripHexPrefix()
        let isTokenAddressed = !sourceToken.isEmpty && to.lowercased() == sourceToken.lowercased()
        guard isTokenAddressed || calldata.hasPrefix(erc20TransferSelector) else { return nil }

        let refuse = { (reason: String) in EVMSwapTxGuardError.swapKitDepositRefused(reason) }
        guard isTokenAddressed else { throw refuse("calls transfer on \(to), not the sold token \(sourceToken)") }
        guard value == 0 else { throw refuse("attaches native value \(value)") }
        guard calldata.count == erc20TransferSelector.count + 128,
              calldata.hasPrefix(erc20TransferSelector + String(repeating: "0", count: 24)),
              calldata.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw refuse("is not exactly an ERC-20 transfer(address,uint256) call")
        }
        let words = calldata.dropFirst(erc20TransferSelector.count)
        guard BigInt(String(words.suffix(64)), radix: 16) == amount else {
            throw refuse("transfers an amount other than the sold amount \(amount)")
        }
        return "0x" + String(words.prefix(64).suffix(40))
    }

    private static let erc20TransferSelector = "a9059cbb"

    private static let enforcedProviders: [SwapProviderId] = [.oneInch, .kyberSwap, .lifi]

    private static func exactValueRouters(chain: Chain) -> Set<String> {
        routers(for: .oneInch, chain: chain).union(routers(for: .kyberSwap, chain: chain))
    }

    private static func routers(for provider: SwapProviderId, chain: Chain) -> Set<String> {
        switch provider {
        case .oneInch:
            switch chain {
            case .zksync: return [oneInchV6ZkSync]
            case .robinhood: return [oneInchV6Robinhood]
            default: return [oneInchV6Standard, oneInchV5]
            }
        case .kyberSwap:
            return [kyber]
        case .lifi:
            switch chain {
            case .hyperliquid: return [lifiHyperliquid]
            case .robinhood: return [lifiRobinhood]
            case .zksync: return [lifiZkSync]
            default: return [lifiDiamond]
            }
        case .swapkit, .jupiter, .unknown:
            return []
        }
    }

    private static let oneInchV5 = "0x1111111254eeb25477b68fb85ed929f73a960582"
    private static let oneInchV6Standard = "0x111111125421ca6dc452d289314280a0f8842a65"
    private static let oneInchV6ZkSync = "0x6fd4383cb451173d5f9304f041c7bcbf27d561ff"
    private static let oneInchV6Robinhood = "0x5a705de8982235a7fa45bb83dcacf03a211389c7"
    private static let kyber = "0x6131b5fae19ea4f9d964eac0408e4408b66337b5"
    private static let lifiDiamond = "0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae"
    private static let lifiHyperliquid = "0x0a0758d937d1059c356d4714e57f5df0239bce1a"
    private static let lifiRobinhood = "0xb477751b76cf82d00a686a1232f5fcd772414af3"
    private static let lifiZkSync = "0x341e94069f53234fe6dabef707ad424830525715"
}
