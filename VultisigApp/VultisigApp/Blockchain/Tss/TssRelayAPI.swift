//
//  TssRelayAPI.swift
//  VultisigApp
//

import Foundation
import Mediator

/// TargetType for the TSS relay/mediator server. The relay host is per-session
/// (passed in at runtime as the mediator URL), so this takes a caller-supplied
/// `baseURL`. Bodies are AES-GCM-encrypted at the call site before being handed
/// to the transport — the relay sees only opaque ciphertext.
struct TssRelayAPI: TargetType {
    let baseURL: URL
    let endpoint: Endpoint

    enum Endpoint {
        /// POST /setup-message/{sessionID}. `body` is already-encrypted UTF-8 bytes.
        /// When `additionalHeader` is non-nil it overrides `messageID` on the
        /// `message_id` header, letting callers route a setup payload into a
        /// different namespace than the TSS exchange.
        case uploadSetupMessage(sessionID: String, body: Data, messageID: String?, additionalHeader: String?)
        case downloadSetupMessage(sessionID: String, messageID: String?, additionalHeader: String?)
        /// POST /message/{sessionID}. The encrypted body sits inside `Message.body`.
        /// `addLegacyKeygenHeader` adds the GG20-only `keygen: vultisig` header.
        case sendMessage(sessionID: String, message: Message, messageID: String?, addLegacyKeygenHeader: Bool)
        /// GET /message/{sessionID}/{localPartyID}. Returns `[Message]`; non-2xx is an error.
        case pollInboundMessages(sessionID: String, localPartyID: String, messageID: String?)
        case deleteMessage(sessionID: String, localPartyID: String, hash: String, messageID: String?)
        /// GET /start/{sessionID}. 404 means "not started yet" and is a valid response.
        case checkKeygenStarted(sessionID: String)
    }

    var path: String {
        switch endpoint {
        case .uploadSetupMessage(let sessionID, _, _, _),
             .downloadSetupMessage(let sessionID, _, _):
            return "/setup-message/\(sessionID)"
        case .sendMessage(let sessionID, _, _, _):
            return "/message/\(sessionID)"
        case .pollInboundMessages(let sessionID, let localPartyID, _):
            return "/message/\(sessionID)/\(localPartyID)"
        case .deleteMessage(let sessionID, let localPartyID, let hash, _):
            return "/message/\(sessionID)/\(localPartyID)/\(hash)"
        case .checkKeygenStarted(let sessionID):
            return "/start/\(sessionID)"
        }
    }

    var method: HTTPMethod {
        switch endpoint {
        case .uploadSetupMessage, .sendMessage:
            return .post
        case .downloadSetupMessage, .pollInboundMessages, .checkKeygenStarted:
            return .get
        case .deleteMessage:
            return .delete
        }
    }

    var task: HTTPTask {
        switch endpoint {
        case .uploadSetupMessage(_, let body, _, _):
            return .requestData(body)
        case .sendMessage(_, let message, _, _):
            return .requestCodable(message, .jsonEncoding)
        case .downloadSetupMessage, .pollInboundMessages, .deleteMessage, .checkKeygenStarted:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        var result: [String: String] = ["Content-Type": "application/json"]

        switch endpoint {
        case .uploadSetupMessage(_, _, let messageID, let additionalHeader),
             .downloadSetupMessage(_, let messageID, let additionalHeader):
            // self.messageID is applied first; additionalHeader overrides it when non-nil.
            if let messageID {
                result["message_id"] = messageID
            }
            if let additionalHeader {
                result["message_id"] = additionalHeader
            }

        case .sendMessage(_, _, let messageID, let addLegacyKeygenHeader):
            if let messageID {
                result["message_id"] = messageID
            }
            if addLegacyKeygenHeader {
                result["keygen"] = "vultisig"
            }

        case .pollInboundMessages(_, _, let messageID),
             .deleteMessage(_, _, _, let messageID):
            if let messageID {
                result["message_id"] = messageID
            }

        case .checkKeygenStarted:
            break
        }

        return result
    }

    var validationType: ValidationType {
        switch endpoint {
        case .checkKeygenStarted:
            // 404 is the relay's "not started yet" signal — surface it as a
            // status code instead of an error so the caller can branch.
            return .customCodes([200, 404])
        case .uploadSetupMessage, .downloadSetupMessage,
             .sendMessage, .pollInboundMessages,
             .deleteMessage:
            return .successCodes
        }
    }
}
