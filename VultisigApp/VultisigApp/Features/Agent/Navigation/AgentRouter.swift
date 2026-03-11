//
//  AgentRouter.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentRouter {

    @ViewBuilder
    func build(_ route: AgentRoute) -> some View {
        switch route {
        case .conversations:
            AgentConversationsView()
        case .chat(let conversationId):
            AgentChatView(conversationId: conversationId)
        }
    }
}
