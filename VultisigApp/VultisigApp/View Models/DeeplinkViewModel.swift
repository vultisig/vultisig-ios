//
//  DeeplinkViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-01.
//

import SwiftUI

enum DeeplinkFlowType {
    case NewVault
    case SignTransaction
    case Send
    case ConnectDapp
    case SignMessage
    case Unknown
}

@MainActor
class DeeplinkViewModel: ObservableObject {
    @Published var type: DeeplinkFlowType? = nil
    @Published var selectedVault: Vault? = nil
    @Published var tssType: TssType? = nil
    @Published var jsonData: String? = nil
    @Published var receivedUrl: URL? = nil
    @Published var viewID = UUID()
    @Published var address: String? = nil

    // Properties for Send deeplink flow
    @Published var assetChain: String? = nil
    @Published var assetTicker: String? = nil
    @Published var sendAmount: String? = nil
    @Published var sendMemo: String? = nil
    @Published var pendingSendDeeplink: Bool = false
    @Published var pendingConnectDeeplink: Bool = false
    @Published var isInternalDeeplink: Bool = false
    @Published var dappUrl: String? = nil
    @Published var callbackUrl: String? = nil

    private let logic = DeeplinkLogic()

    @discardableResult
    func extractParameters(_ url: URL, vaults: [Vault], isInternal: Bool = false) throws -> Bool {
        resetFieldsForExtraction()
        isInternalDeeplink = isInternal
        viewID = UUID()
        receivedUrl = url

        let result = try logic.extractParameters(url, vaults: vaults)
        apply(result: result)

        if result.shouldNotify {
            NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
            return true
        }

        return false
    }

    static func getJsonData(_ url: URL?) -> String? {
        DeeplinkLogic.getJsonData(url)
    }

    static func getTssType(_ url: URL?) -> String? {
        DeeplinkLogic.getTssType(url)
    }

    func resetData() {
        type = nil
        resetFieldsForExtraction()
        isInternalDeeplink = false
    }

    func findCoin(in vault: Vault) -> Coin? {
        logic.findCoin(in: vault, assetChain: assetChain, assetTicker: assetTicker)
    }

    private func resetFieldsForExtraction() {
        selectedVault = nil
        tssType = nil
        jsonData = nil
        receivedUrl = nil
        address = nil
        assetChain = nil
        assetTicker = nil
        sendAmount = nil
        sendMemo = nil
        pendingSendDeeplink = false
        pendingConnectDeeplink = false
        dappUrl = nil
        callbackUrl = nil
    }

    private func apply(result: DeeplinkLogic.DeeplinkResult) {
        type = result.type
        selectedVault = result.selectedVault
        tssType = result.tssType
        jsonData = result.jsonData
        address = result.address
        assetChain = result.assetChain
        assetTicker = result.assetTicker
        sendAmount = result.sendAmount
        sendMemo = result.sendMemo
        pendingSendDeeplink = result.pendingSendDeeplink
        dappUrl = result.dappUrl
        callbackUrl = result.callbackUrl
    }
}

struct DeeplinkLogic {
    struct DeeplinkResult {
        var type: DeeplinkFlowType?
        var selectedVault: Vault?
        var tssType: TssType?
        var jsonData: String?
        var address: String?
        var assetChain: String?
        var assetTicker: String?
        var sendAmount: String?
        var sendMemo: String?
        var pendingSendDeeplink: Bool = false
        var shouldNotify: Bool = false
        var dappUrl: String?
        var callbackUrl: String?
    }

    func extractParameters(_ url: URL, vaults: [Vault]) throws -> DeeplinkResult {
        guard let urlComponents = URLComponents(string: url.absoluteString) else {
            return buildAddressOnlyResult(url: url)
        }

        let queryItems = urlComponents.queryItems
        let path = urlComponents.path.lowercased()
        let host = urlComponents.host?.lowercased() ?? ""
        let urlString = url.absoluteString.lowercased()
        let pathComponents = path.split(separator: "/").map { String($0) }

        let isSendPath = path.contains("send") ||
            pathComponents.contains("send") ||
            host == "send" ||
            host.contains("send") ||
            urlString.contains("://send") ||
            urlString.hasPrefix("vultisig://send")

        let isConnectPath = path.contains("connect") ||
            pathComponents.contains("connect") ||
            host == "connect" ||
            host.contains("connect") ||
            urlString.contains("://connect") ||
            urlString.hasPrefix("vultisig://connect")

        if isSendPath {
            return processSendDeeplink(queryItems: queryItems, vaults: vaults)
        } else if isConnectPath {
            return processConnectDeeplink(queryItems: queryItems, vaults: vaults)
        } else if queryItems == nil {
            return buildAddressOnlyResult(url: url)
        } else {
            var result = try processKeygenOrKeysignDeeplink(queryItems: queryItems, vaults: vaults)
            if result.type != nil {
                result.shouldNotify = true
            }
            return result
        }
    }

    func findCoin(in vault: Vault, assetChain: String?, assetTicker: String?) -> Coin? {
        guard let assetChain = assetChain,
              let assetTicker = assetTicker else {
            return nil
        }

        let chainString = assetChain.lowercased()
        guard let chain = Chain.allCases.first(where: { $0.rawValue.lowercased() == chainString }) else {
            return nil
        }

        let tickerUpper = assetTicker.uppercased()
        return vault.coins.first { coin in
            coin.chain == chain && coin.ticker.uppercased() == tickerUpper
        }
    }

    static func getJsonData(_ url: URL?) -> String? {
        guard let url,
              let components = URLComponents(string: url.absoluteString) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "jsonData" })?.value
    }

    static func getTssType(_ url: URL?) -> String? {
        guard let url,
              let components = URLComponents(string: url.absoluteString) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "tssType" })?.value
    }

    private func buildAddressOnlyResult(url: URL) -> DeeplinkResult {
        var result = DeeplinkResult()
        let addressString = url.absoluteString.replacingOccurrences(of: "vultisig://", with: "")
        result.address = Utils.sanitizeAddress(address: addressString)
        result.type = .Unknown
        result.shouldNotify = true
        return result
    }

    private func processSendDeeplink(queryItems: [URLQueryItem]?, vaults: [Vault]) -> DeeplinkResult {
        var result = DeeplinkResult()
        result.type = .Send
        result.assetChain = queryItems?.first(where: { $0.name == "assetChain" })?.value?.removingPercentEncoding
        result.assetTicker = queryItems?.first(where: { $0.name == "assetTicker" })?.value?.removingPercentEncoding
        result.address = queryItems?.first(where: { $0.name == "toAddress" })?.value?.removingPercentEncoding
        result.sendAmount = queryItems?.first(where: { $0.name == "amount" })?.value?.removingPercentEncoding
        result.sendMemo = queryItems?.first(where: { $0.name == "memo" })?.value?.removingPercentEncoding
        result.pendingSendDeeplink = true

        if result.address == nil || result.address?.isEmpty == true {
            result.type = .Unknown
            return result
        }

        if let chainName = result.assetChain {
            result.selectedVault = vaults.first { vault in
                vault.coins.contains { $0.chain.name.lowercased() == chainName.lowercased() }
            }
        }

        result.shouldNotify = true
        return result
    }

    private func processConnectDeeplink(queryItems: [URLQueryItem]?, vaults: [Vault]) -> DeeplinkResult {
        var result = DeeplinkResult()
        result.type = .ConnectDapp
        result.dappUrl = queryItems?.first(where: { $0.name == "dappUrl" })?.value?.removingPercentEncoding
        result.callbackUrl = queryItems?.first(where: { $0.name == "callback" })?.value?.removingPercentEncoding
        result.assetChain = queryItems?.first(where: { $0.name == "chain" })?.value?.removingPercentEncoding
        result.shouldNotify = true
        return result
    }

    private func processKeygenOrKeysignDeeplink(queryItems: [URLQueryItem]?, vaults: [Vault]) throws -> DeeplinkResult {
        var result = DeeplinkResult()

        let typeData = queryItems?.first(where: { $0.name == "type" })?.value
        result.type = parseFlowType(typeData)

        let vaultPubKey = queryItems?.first(where: { $0.name == "vault" })?.value
        let vault = getVault(for: vaultPubKey, vaults: vaults)

        if vault == nil && result.type == .SignTransaction {
            throw UtilsQrCodeFromImageError.VaultNotImported(publicKey: vaultPubKey ?? "")
        }

        result.selectedVault = vault

        let tssData = queryItems?.first(where: { $0.name == "tssType" })?.value
        result.tssType = parseTssType(tssData)

        result.jsonData = queryItems?.first(where: { $0.name == "jsonData" })?.value
        return result
    }

    private func parseFlowType(_ value: String?) -> DeeplinkFlowType? {
        switch value {
        case "NewVault":
            return .NewVault
        case "SignTransaction":
            return .SignTransaction
        case "SignMessage":
            return .SignMessage
        case "Send":
            return .Send
        default:
            return .Unknown
        }
    }

    private func parseTssType(_ value: String?) -> TssType? {
        switch value {
        case "Reshare":
            return .Reshare
        default:
            return .Keygen
        }
    }

    private func getVault(for vaultPubKey: String?, vaults: [Vault]) -> Vault? {
        guard let vaultPubKey else {
            return nil
        }
        return vaults.first(where: { $0.pubKeyECDSA == vaultPubKey })
    }
}

enum DeeplinkError: Error, ErrorWithCustomPresentation {
    case unrelatedQRCode
    case chainNotAdded(chainName: String)

    var errorTitle: String {
        switch self {
        case .unrelatedQRCode:
            return NSLocalizedString("unrelatedQRCode", comment: "")
        case .chainNotAdded:
            return NSLocalizedString("chainNotAdded", comment: "")
        }
    }

    var errorDescription: String {
        switch self {
        case .unrelatedQRCode:
            return NSLocalizedString("unrelatedQRCodeMessage", comment: "")
        case .chainNotAdded(let chainName):
            return String(
                format: NSLocalizedString("chainNotAddedMessage", comment: ""),
                chainName
            )
        }
    }
}
