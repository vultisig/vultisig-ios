//
//  ForegroundNotificationParser.swift
//  VultisigApp
//

import Foundation
import UserNotifications

enum ForegroundNotificationParser {

    static func parse(
        notification: UNNotification,
        vaults: [Vault]
    ) -> ForegroundNotificationData? {
        let userInfo = notification.request.content.userInfo

        guard let deeplinkString = userInfo["deeplink"] as? String,
              let deeplinkURL = URL(string: deeplinkString) else {
            return nil
        }

        let components = URLComponents(string: deeplinkString)
        let queryItems = components?.queryItems

        let vaultPubKey = queryItems?.first(where: { $0.name == "vault" })?.value
        let vault = vaults.first(where: { $0.pubKeyECDSA == vaultPubKey })

        let vaultName = vault?.name ?? "unknown".localized
        let isFastVault = vault?.isFastVault ?? false

        let transactionType = parseTransactionType(
            queryItems: queryItems,
            notificationBody: notification.request.content.body
        )

        return ForegroundNotificationData(
            transactionType: transactionType,
            vaultName: vaultName,
            isFastVault: isFastVault,
            deeplinkURL: deeplinkURL
        )
    }

    private static func parseTransactionType(
        queryItems: [URLQueryItem]?,
        notificationBody: String
    ) -> ForegroundNotificationData.TransactionType {
        guard let jsonData = queryItems?.first(where: { $0.name == "jsonData" })?.value else {
            return fallbackType(body: notificationBody)
        }

        guard let keysignMessage: KeysignMessage = try? ProtoSerializer.deserialize(
            base64EncodedString: jsonData
        ) else {
            return fallbackType(body: notificationBody)
        }

        guard let payload = keysignMessage.payload else {
            return fallbackType(body: notificationBody)
        }

        if let swapPayload = payload.swapPayload {
            let description = String(
                format: "foregroundNotificationSwap".localized,
                payload.fromAmountString,
                swapPayload.toCoin.ticker
            )
            return .swap(description: description)
        } else {
            let description = String(
                format: "foregroundNotificationSend".localized,
                payload.toAmountWithTickerString
            )
            return .send(description: description)
        }
    }

    private static func fallbackType(
        body: String
    ) -> ForegroundNotificationData.TransactionType {
        if body.isEmpty {
            return .generic(body: "foregroundNotificationGeneric".localized)
        }
        return .generic(body: body)
    }
}
