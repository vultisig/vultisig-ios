//
//  AgentRoute.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation

enum AgentRoute: Hashable {
    case conversations
    case chat(conversationId: String?)
}
