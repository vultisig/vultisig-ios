//
//  AgentModels.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation

// MARK: - Request Types

struct AgentSendMessageRequest: Codable {
    let publicKey: String
    var content: String?
    var model: String?
    var context: AgentMessageContext?
    var selectedSuggestionId: String?
    var actionResult: AgentActionResult?

    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case content
        case model
        case context
        case selectedSuggestionId = "selected_suggestion_id"
        case actionResult = "action_result"
    }
}

struct AgentMessageContext: Codable {
    var vaultAddress: String?
    var vaultName: String?
    var balances: [AgentBalanceInfo]?
    var addresses: [String: String]?
    var coins: [AgentCoinInfo]?
    var addressBook: [AgentAddressBookEntry]?
    var instructions: String?

    enum CodingKeys: String, CodingKey {
        case vaultAddress = "vault_address"
        case vaultName = "vault_name"
        case balances, addresses, coins
        case addressBook = "address_book"
        case instructions
    }
}

struct AgentBalanceInfo: Codable {
    let chain: String
    let asset: String
    let symbol: String
    let amount: String
    let decimals: Int
}

struct AgentCoinInfo: Codable {
    let chain: String
    let ticker: String
    var contractAddress: String?
    let isNativeToken: Bool
    let decimals: Int

    enum CodingKeys: String, CodingKey {
        case chain, ticker
        case contractAddress = "contract_address"
        case isNativeToken = "is_native_token"
        case decimals
    }
}

struct AgentAddressBookEntry: Codable {
    let title: String
    let address: String
    let chain: String
}

struct AgentActionResult: Codable {
    let action: String
    var actionId: String?
    let success: Bool
    var data: [String: AnyCodable]?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case action
        case actionId = "action_id"
        case success, data, error
    }
}

struct AgentGetStartersRequest: Codable {
    let publicKey: String
    var context: AgentMessageContext?

    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case context
    }
}

// MARK: - Response Types

struct AgentSendMessageResponse: Codable {
    var message: AgentBackendMessage?
    var title: String?
    var suggestions: [AgentBackendSuggestion]?
    var actions: [AgentBackendAction]?
    var policyReady: AgentPolicyReady?
    var installRequired: AgentInstallRequired?
    var txReady: AgentTxReady?
    var tokens: [AgentTokenSearchResult]?

    enum CodingKeys: String, CodingKey {
        case message, title, suggestions, actions
        case policyReady = "policy_ready"
        case installRequired = "install_required"
        case txReady = "tx_ready"
        case tokens
    }
}

struct AgentBackendMessage: Codable {
    let id: String
    let conversationId: String
    let role: String
    let content: String
    let contentType: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role, content
        case contentType = "content_type"
        case createdAt = "created_at"
    }
}

struct AgentBackendAction: Codable {
    let id: String
    let type: String
    let title: String
    var description: String?
    var params: [String: AnyCodable]?
    let autoExecute: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, params
        case autoExecute = "auto_execute"
    }
}

struct AgentBackendSuggestion: Codable {
    let id: String
    let pluginId: String
    let title: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case id
        case pluginId = "plugin_id"
        case title, description
    }
}

struct AgentTxReady: Codable {
    var provider: String?
    var expectedOutput: String?
    var minimumOutput: String?
    var needsApproval: Bool?
    var keysignPayload: String?
    let fromChain: String
    let fromSymbol: String
    var toChain: String?
    var toSymbol: String?
    let amount: String
    let sender: String
    let destination: String
    var txType: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case expectedOutput = "expected_output"
        case minimumOutput = "minimum_output"
        case needsApproval = "needs_approval"
        case keysignPayload = "keysign_payload"
        case fromChain = "from_chain"
        case fromSymbol = "from_symbol"
        case toChain = "to_chain"
        case toSymbol = "to_symbol"
        case amount, sender, destination
        case txType = "tx_type"
    }
}

struct AgentPolicyReady: Codable {
    let pluginId: String
    let configuration: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case pluginId = "plugin_id"
        case configuration
    }
}

struct AgentInstallRequired: Codable {
    let pluginId: String
    let title: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case pluginId = "plugin_id"
        case title, description
    }
}

struct AgentGetStartersResponse: Codable {
    let starters: [String]
}

struct AgentListConversationsResponse: Codable {
    let conversations: [AgentConversation]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case conversations
        case totalCount = "total_count"
    }
}

struct AgentTokenSearchResult: Codable {
    var id: String?
    let name: String
    let symbol: String
    var logo: String?
    var logoUrl: String?
    var priceUsd: String?
    var marketCapRank: Int?
    var deployments: [AgentTokenDeployment]?

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, logo
        case logoUrl = "logo_url"
        case priceUsd = "price_usd"
        case marketCapRank = "market_cap_rank"
        case deployments
    }
}

struct AgentTokenDeployment: Codable {
    let chain: String
    let contractAddress: String
    var decimals: Int?

    enum CodingKeys: String, CodingKey {
        case chain
        case contractAddress = "contract_address"
        case decimals
    }
}

// MARK: - Tool Calls (MCP)

struct AgentAddTokenParams: Codable {
    let tokens: [AgentTokenParam]
}

struct AgentTokenParam: Codable {
    let chain: String
    let ticker: String
    var contractAddress: String?
    var decimals: Int?
    var logo: String?
    var priceProviderId: String?
    var isNative: Bool?

    enum CodingKeys: String, CodingKey {
        case chain, ticker, decimals, logo
        case contractAddress = "contract_address"
        case priceProviderId = "price_provider_id"
        case isNative = "is_native"
    }
}

struct AgentAddTokenResult: Codable {
    let chain: String
    let ticker: String
    var address: String?
    var contractAddress: String?
    let success: Bool
    var error: String?
    var chainAdded: Bool?

    enum CodingKeys: String, CodingKey {
        case chain, ticker, address, success, error
        case contractAddress = "contract_address"
        case chainAdded = "chain_added"
    }
}

struct AgentAddChainParams: Codable {
    let chains: [AgentChainParam]
}

struct AgentChainParam: Codable {
    let chain: String
}

struct AgentAddChainResult: Codable {
    let chain: String
    var ticker: String?
    var address: String?
    let success: Bool
    var error: String?
}

struct AgentGetAddressBookParams: Codable {
    var chain: String?
    var query: String?
}

struct AgentGetAddressBookResult: Codable {
    let entries: [AgentAddressBookEntryResult]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case entries
        case totalCount = "total_count"
    }
}

struct AgentAddressBookEntryResult: Codable {
    let id: String
    let title: String
    let address: String
    let chain: String
    var chainKind: String?

    enum CodingKeys: String, CodingKey {
        case id, title, address, chain
        case chainKind = "chain_kind"
    }
}

struct AgentAddAddressBookParams: Codable {
    let entries: [AgentAddAddressBookEntryParam]
}

struct AgentAddAddressBookEntryParam: Codable {
    let title: String
    let address: String
    let chain: String
}

struct AgentAddAddressBookResult: Codable {
    let id: String
    let title: String
    let address: String
    let chain: String
    let success: Bool
    var error: String?
}

struct AgentDeleteAddressBookParams: Codable {
    let entries: [AgentDeleteAddressBookEntryParam]
}

struct AgentDeleteAddressBookEntryParam: Codable {
    var id: String?
    var title: String?
    var address: String?
    var chain: String?
}

struct AgentDeleteAddressBookResult: Codable {
    var id: String?
    let title: String?
    let chain: String?
    let success: Bool
    var error: String?
}

// MARK: - Conversation

struct AgentConversation: Codable, Identifiable, Hashable {
    let id: String
    let publicKey: String
    var title: String?
    let createdAt: String
    let updatedAt: String
    var archivedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case publicKey = "public_key"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AgentConversation, rhs: AgentConversation) -> Bool {
        lhs.id == rhs.id
    }
}

struct AgentConversationWithMessages: Codable {
    let id: String
    let publicKey: String
    var title: String?
    let createdAt: String
    let updatedAt: String
    let messages: [AgentBackendMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case publicKey = "public_key"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messages
    }
}

// MARK: - Auth Token

struct AgentAuthToken: Codable {
    let token: String
    let refreshToken: String
    let expiresAt: Date
}

struct AgentAuthData: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct AgentAuthResponse: Codable {
    let data: AgentAuthData
}

// MARK: - SSE Event

enum AgentSSEEvent {
    case textDelta(String)
    case title(String)
    case actions([AgentBackendAction])
    case suggestions([AgentBackendSuggestion])
    case txReady(AgentTxReady)
    case tokens([AgentTokenSearchResult])
    case message(AgentBackendMessage)
    case error(String)
    case done
}

// MARK: - Chat UI Types

struct AgentChatMessage: Identifiable {
    let id: String
    let role: AgentChatRole
    var content: String
    let timestamp: Date
    var toolCall: AgentToolCallInfo?
    var txStatus: AgentTxStatusInfo?
    var tokenResults: [AgentTokenSearchResult]?
}

enum AgentChatRole {
    case user
    case assistant
}

struct AgentToolCallInfo {
    let actionType: String
    let title: String
    var params: [String: AnyCodable]?
    var status: AgentToolCallStatus
    var resultData: [String: AnyCodable]?
    var error: String?
}

enum AgentToolCallStatus {
    case running
    case success
    case error
}

struct AgentTxStatusInfo {
    let txHash: String
    let chain: String
    var status: AgentTxStatus
    let label: String
}

enum AgentTxStatus {
    case pending
    case confirmed
    case failed
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}
