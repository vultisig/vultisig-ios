//
//  SwapDeliveredAmountService.swift
//  VultisigApp
//
//  Reads the delivered amount of a completed swap (see `SwapDeliveredAmount`
//  for which sources state it). Read-only: Midgard actions and an EVM receipt.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-delivered-amount")

struct SwapDeliveredAmountService {
    var httpClient: HTTPClientProtocol = HTTPClient()

    /// Values captured on the main actor from the transaction, so the fetch
    /// never touches a SwiftData model off it.
    struct Request: Sendable {
        enum Source: Sendable {
            case midgard(network: Chain, asset: String, divisor: Decimal)
            case evmReceipt(chain: Chain, token: String, decimals: Int)
        }

        let hash: String
        let recipient: String
        let source: Source
    }

    /// Nil when the route has no source that states the delivered amount.
    @MainActor
    static func request(for transaction: SwapTransaction, hash: String) -> Request? {
        guard let quote = transaction.quote else { return nil }
        let toCoin = transaction.toCoin
        // The external recipient when one is set, the vault's address otherwise.
        let recipient = transaction.recipientAddress
        if quote.isNativeProtocolRoute, let network = NativeSwapTrackingService.network(for: quote) {
            // Full canonical spelling (contract included, secured denoms as
            // is). Without one there is no way to tell the asset apart: nil.
            guard let asset = thorchainCancelMemoAsset(for: toCoin) else { return nil }
            let divisor: Decimal = network == .mayaChain ? toCoin.thorswapMultiplier : pow(10, 8)
            return Request(hash: hash, recipient: recipient, source: .midgard(network: network, asset: asset, divisor: divisor))
        }
        switch quote {
        case .oneinch, .kyberswap, .lifi:
            guard transaction.fromCoin.chain == toCoin.chain,
                  toCoin.chain.chainType == .EVM,
                  !toCoin.isNativeToken else { return nil }
            return Request(
                hash: hash,
                recipient: recipient,
                source: .evmReceipt(chain: toCoin.chain, token: toCoin.contractAddress, decimals: toCoin.decimals)
            )
        default:
            return nil
        }
    }

    func deliveredAmount(_ request: Request) async -> Decimal? {
        do {
            switch request.source {
            case let .midgard(network, asset, divisor):
                let response = try await httpClient.request(
                    THORChainTransactionStatusAPI.getActions(txHash: request.hash, chain: network),
                    responseType: THORChainActionsResponse.self
                ).data
                // Same settlement rule the tracker uses, on this response.
                guard NativeSwapTrackingService.outcome(response: response, hash: request.hash)?.status == "completed" else {
                    return nil
                }
                return SwapDeliveredAmount.fromMidgard(
                    actions: response.actions,
                    count: response.count,
                    inboundHash: request.hash,
                    recipient: request.recipient,
                    asset: asset,
                    divisor: divisor
                )
            case let .evmReceipt(chain, token, decimals):
                let config = try EvmServiceConfig.getConfig(forChain: chain)
                let receipt = try await RpcEvmService(config.rpcEndpoint).sendRPCRequest(
                    method: "eth_getTransactionReceipt",
                    params: [request.hash]
                ) { $0 as? [String: Any] }
                guard let receipt else { return nil }
                return SwapDeliveredAmount.fromReceiptLogs(
                    SwapDeliveredAmount.logs(fromReceipt: receipt),
                    token: token,
                    recipient: request.recipient,
                    decimals: decimals
                )
            }
        } catch {
            logger.warning("Delivered amount unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
