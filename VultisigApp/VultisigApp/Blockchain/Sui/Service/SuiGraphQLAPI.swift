//
//  SuiGraphQLAPI.swift
//  VultisigApp
//

import Foundation

/// Pure `TargetType` for Sui's GraphQL RPC endpoint.
///
/// Sui is retiring JSON-RPC: shutdown on Foundation mainnet full nodes began the
/// week of 2026-07-27 and full decommission — code removal from `sui-node`,
/// after which no provider can serve it — lands mid-October 2026. gRPC and
/// GraphQL RPC are the supported replacements.
///
/// GraphQL was chosen over gRPC because it is a plain JSON POST that the app's
/// existing `TargetType` / `HTTPClient` layer already speaks, keeping the custom
/// RPC override, the failover walk, logging, timeouts and cancellation exactly
/// as they were. gRPC would have required raising the deployment target — the
/// only maintained Swift gRPC package declares `iOS 18` / `macOS 15` while this
/// app ships `iOS 17` — plus roughly a dozen new SPM packages and a Protobuf
/// codegen step over 41 vendored `.proto` files.
///
/// The host is baked in at construction by the caller (see `SuiEndpointResolver`);
/// this value never consults global state. Everything posts to the same endpoint,
/// so the path is always empty.
struct SuiGraphQLAPI: TargetType {

    /// Sui's public GraphQL RPC endpoint.
    static let defaultHost = URL(staticString: "https://graphql.mainnet.sui.io/graphql")

    /// Hosts attempted in order when the user has not configured a custom RPC.
    ///
    /// One entry today: this is the only public Sui GraphQL endpoint that
    /// answers. `sui-rpc.publicnode.com` and Vultisig's own `api.vultisig.com/sui`
    /// proxy are deliberately absent — both speak JSON-RPC only, so they are
    /// subject to the same decommission and cannot serve as a fallback until
    /// their backends move. Adding a second host is a one-line change here;
    /// `SuiFailoverClient` already walks the whole list.
    static let defaultHosts: [URL] = [defaultHost]

    let baseURL: URL
    let document: String
    let variables: [String: Any]

    init(baseURL: URL = SuiGraphQLAPI.defaultHost, document: String, variables: [String: Any] = [:]) {
        self.baseURL = baseURL
        self.document = document
        self.variables = variables
    }

    var path: String { "" }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        .requestParameters(["query": document, "variables": variables], .jsonEncoding)
    }
}

/// The GraphQL documents the app sends, kept together so the selection sets and
/// the types that decode them can be read side by side.
///
/// Every one was executed against `graphql.mainnet.sui.io` before being written
/// down, against real mainnet data.
enum SuiGraphQLDocument {

    /// Page size for the coin-object connection, matching the JSON-RPC default
    /// this replaces.
    static let coinPageSize = 50

    /// Replaces `suix_getAllBalances`. The app only ever wanted the balance of
    /// one coin type, so this asks for exactly that instead of paginating the
    /// whole `balances` connection and filtering client-side.
    static let balance = """
    query getBalance($owner: SuiAddress!, $coinType: String!) {
      address(address: $owner) {
        balance(coinType: $coinType) { totalBalance }
      }
    }
    """

    /// Replaces `suix_getReferenceGasPrice`.
    static let referenceGasPrice = "query { epoch { referenceGasPrice } }"

    /// Replaces `suix_getAllCoins`. Filtered to `0x2::coin::Coin` so the
    /// connection returns coin objects only — no NFTs — and paginated.
    static let allCoins = """
    query getAllCoins($owner: SuiAddress!, $cursor: String) {
      address(address: $owner) {
        objects(first: \(coinPageSize), after: $cursor, filter: { type: "0x2::coin::Coin" }) {
          pageInfo { hasNextPage endCursor }
          nodes {
            address
            version
            digest
            contents { type { repr } json }
          }
        }
      }
    }
    """

    /// Replaces `suix_getCoinMetadata`.
    static let coinMetadata = """
    query getCoinMetadata($coinType: String!) {
      coinMetadata(coinType: $coinType) { decimals symbol iconUrl }
    }
    """

    /// Replaces `sui_executeTransactionBlock`.
    ///
    /// `transactionDataBcs` and `signatures` take the same base64 strings the
    /// JSON-RPC call took, forwarded verbatim from the signing path.
    static let executeTransaction = """
    mutation executeTransaction($txBytes: Base64!, $signatures: [Base64!]!) {
      executeTransaction(transactionDataBcs: $txBytes, signatures: $signatures) {
        effects { digest status executionError { message abortCode identifier } }
      }
    }
    """

    /// Replaces `sui_dryRunTransactionBlock`.
    ///
    /// `simulateTransaction` takes a JSON-encoded `sui.rpc.v2.Transaction`, whose
    /// `bcs` field carries the same base64 BCS bytes the JSON-RPC dry run
    /// accepted directly — so the simulated transaction is byte-identical to the
    /// one that gets signed. Gas selection stays off because the caller already
    /// built a complete gas payment; letting the node re-pick it would price a
    /// different transaction than the one being signed.
    static let simulateTransaction = """
    query simulateTransaction($tx: JSON!) {
      simulateTransaction(transaction: $tx, checksEnabled: true, doGasSelection: false) {
        effects {
          digest
          status
          executionError { message abortCode identifier }
          gasEffects { gasSummary { computationCost storageCost storageRebate nonRefundableStorageFee } }
        }
      }
    }
    """

    /// Replaces `sui_getTransactionBlock`.
    static let transaction = """
    query getTransaction($digest: String!) {
      transaction(digest: $digest) {
        digest
        effects {
          status
          executionError { message abortCode identifier }
          checkpoint { sequenceNumber }
        }
      }
    }
    """

    /// Replaces `sui_getLatestCheckpointSequenceNumber` (the custom-RPC health
    /// probe).
    static let latestCheckpoint = "query { checkpoint { sequenceNumber } }"

    /// The `simulateTransaction` argument for already-serialized bytes.
    static func bcsTransaction(_ base64: String) -> [String: Any] {
        ["bcs": ["value": base64]]
    }
}
