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
            case midgard(network: Chain, assetPrefix: String?, divisor: Decimal)
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
        if quote.isNativeProtocolRoute, let network = NativeSwapTrackingService.network(for: quote) {
            let prefix = thorchainChainPrefix(for: toCoin.chain).map { "\($0).\(toCoin.ticker.uppercased())" }
            let divisor: Decimal = network == .mayaChain ? toCoin.thorswapMultiplier : pow(10, 8)
            return Request(hash: hash, recipient: toCoin.address, source: .midgard(network: network, assetPrefix: prefix, divisor: divisor))
        }
        switch quote {
        case .oneinch, .kyberswap, .lifi:
            guard transaction.fromCoin.chain == toCoin.chain,
                  toCoin.chain.chainType == .EVM,
                  !toCoin.isNativeToken else { return nil }
            return Request(
                hash: hash,
                recipient: toCoin.address,
                source: .evmReceipt(chain: toCoin.chain, token: toCoin.contractAddress, decimals: toCoin.decimals)
            )
        default:
            return nil
        }
    }

    func deliveredAmount(_ request: Request) async -> Decimal? {
        do {
            switch request.source {
            case let .midgard(network, assetPrefix, divisor):
                let response = try await httpClient.request(
                    THORChainTransactionStatusAPI.getActions(txHash: request.hash, chain: network),
                    responseType: THORChainActionsResponse.self
                ).data
                return SwapDeliveredAmount.fromMidgard(
                    actions: response.actions,
                    inboundHash: request.hash,
                    recipient: request.recipient,
                    assetPrefix: assetPrefix,
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
