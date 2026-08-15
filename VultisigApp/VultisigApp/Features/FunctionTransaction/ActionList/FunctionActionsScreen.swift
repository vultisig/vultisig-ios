//
//  FunctionActionsScreen.swift
//  VultisigApp
//
//  The operations a chain offers, one row each, every row a destination.
//
//  There is no selected row and no default. The screen it replaces opened on
//  `FunctionCallType.getDefault(for:)` and then rendered that operation's form
//  inline, which is why a chain could open on a form its own dropdown never
//  offered. A list cannot express that state: the user arrives having chosen
//  nothing, and every row leads somewhere it can actually go.
//

import SwiftUI

struct FunctionActionsScreen: View {
    @Environment(\.router) var router

    let vault: Vault
    let coin: Coin
    let descriptors: [FunctionActionDescriptor]

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                if descriptors.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .screenTitle("functionActionsTitle".localized)
    }

    var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                FunctionActionRow(descriptor: descriptor) {
                    select(descriptor)
                }
                .commonListItemContainer(index: index, itemsCount: descriptors.count)
            }
        }
        .commonListContainer()
    }

    var emptyState: some View {
        Text("functionActionsEmptyDescription".localized)
            .font(Theme.fonts.bodySRegular)
            .foregroundStyle(Theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
    }

    func select(_ descriptor: FunctionActionDescriptor) {
        router.navigate(
            to: FunctionCallRoute.route(for: descriptor.destination, vault: vault)
        )
    }
}
