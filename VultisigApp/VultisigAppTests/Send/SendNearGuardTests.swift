//
//  SendNearGuardTests.swift
//  VultisigAppTests
//
//  The pre-ceremony NEAR guards `SendCryptoVerifyViewModel.validateForm` runs,
//  against a scripted JSON-RPC node.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SendNearGuardTests: XCTestCase {

    private static let sender = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    private static let receiver = "wrap.near"

    /// nearcore's upfront reservation for a named receiver at 1e8 yocto/gas (`Near.namedGasFee`).
    private static let quotedGas = BigInt("245500818750000000000")
    /// 1,000 bytes at 1e19 yocto per byte.
    private static let storageReserve = BigInt("10000000000000000000000")
    private static let sendAmount = BigInt("500000000000000000000000") // 0.5 NEAR

    private var token: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func testStorageReserveIsCheckedAgainstTheGasThePayloadSigns() async throws {
        let signedGas = Self.quotedGas * 2
        // Covers the send with the quoted gas, but not with the gas the payload carries.
        let balance = Self.sendAmount + Self.storageReserve + Self.quotedGas + BigInt("100000000000000000000")
        let node = ScriptedNearNode(accounts: [
            Self.sender: (amount: balance, storageUsage: 1_000),
            Self.receiver: (amount: BigInt(1), storageUsage: 182)
        ])
        let vm = makeVerifyViewModel(node: node, signedGas: signedGas, balance: balance)

        do {
            _ = try await vm.validateForm()
            XCTFail("a balance short of the signed gas reservation must not reach signing")
        } catch {
            XCTAssertEqual(error.localizedDescription, "walletBalanceExceededError")
        }
    }

    func testANamedReceiverTheNodeDoesNotKnowIsRefusedBeforeSigning() async throws {
        let balance = BigInt("1000000000000000000000000") // 1 NEAR
        let node = ScriptedNearNode(accounts: [Self.sender: (amount: balance, storageUsage: 182)])
        let vm = makeVerifyViewModel(node: node, signedGas: Self.quotedGas, balance: balance)

        do {
            _ = try await vm.validateForm()
            XCTFail("a send to a named account that does not exist must not reach signing")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                String(format: "nearUnknownReceiverError".localized, Self.receiver)
            )
        }
    }

    func testAReceiverLookupThatFailsRefusesTheSend() async throws {
        let balance = BigInt("1000000000000000000000000") // 1 NEAR
        let node = ScriptedNearNode(
            accounts: [Self.sender: (amount: balance, storageUsage: 182)],
            unreachableAccounts: [Self.receiver]
        )
        let vm = makeVerifyViewModel(node: node, signedGas: Self.quotedGas, balance: balance)

        do {
            _ = try await vm.validateForm()
            XCTFail("a receiver lookup that failed must not let the send reach signing")
        } catch {
            XCTAssertNotEqual(
                error.localizedDescription,
                String(format: "nearUnknownReceiverError".localized, Self.receiver)
            )
        }
    }

    // MARK: - Builders

    private func makeVerifyViewModel(node: ScriptedNearNode, signedGas: BigInt, balance: BigInt) -> SendCryptoVerifyViewModel {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Near(
                nonce: 2,
                blockHash: Data(repeating: 1, count: 32),
                gasFee: signedGas.description,
                storageReserve: Self.storageReserve
            )
        }
        let near = Coin(
            asset: CoinMeta.make(chain: .near, ticker: "NEAR", decimals: 24, isNativeToken: true),
            address: Self.sender,
            hexPublicKey: Self.sender
        )
        near.rawBalance = balance.description
        let tx = SendTransaction(
            coin: near,
            vault: TestStore.makeVault(),
            fromAddress: Self.sender,
            toAddress: Self.receiver,
            toAddressLabel: nil,
            amount: SendCryptoLogic.amountString(coin: near, raw: Self.sendAmount),
            amountInFiat: "",
            memo: "",
            gas: Self.quotedGas,
            fee: Self.quotedGas,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: near
        )
        let vm = SendCryptoVerifyViewModel(
            transaction: tx,
            interactor: interactor,
            nearService: NearService(client: node)
        )
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        return vm
    }
}

/// Answers `view_account` from `accounts` (UNKNOWN_ACCOUNT otherwise, a node
/// timeout for `unreachableAccounts`) and `EXPERIMENTAL_protocol_config` with
/// nearcore 2.13.4's costs.
private final class ScriptedNearNode: HTTPClientProtocol, @unchecked Sendable {
    private let accounts: [String: (amount: BigInt, storageUsage: Int)]
    private let unreachableAccounts: Set<String>

    init(accounts: [String: (amount: BigInt, storageUsage: Int)], unreachableAccounts: Set<String> = []) {
        self.accounts = accounts
        self.unreachableAccounts = unreachableAccounts
    }

    // Protocol requires `async`; the body is synchronous.
    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard case let .requestData(body) = target.task,
              let request = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = request["method"] as? String,
              let params = request["params"] as? [String: Any] else {
            throw HTTPError.invalidURL
        }

        let json: String
        switch (method, params["request_type"] as? String) {
        case ("query", "view_account"):
            let accountId = params["account_id"] as? String ?? ""
            if unreachableAccounts.contains(accountId) {
                json = #"{"jsonrpc":"2.0","id":"query","error":{"name":"HANDLER_ERROR","cause":{"name":"TIMEOUT_ERROR"},"message":"Server error","data":"Timeout"}}"#
            } else if let account = accounts[accountId] {
                json = #"{"jsonrpc":"2.0","id":"query","result":{"amount":"\#(account.amount)","locked":"0","storage_usage":\#(account.storageUsage)}}"#
            } else {
                json = #"{"jsonrpc":"2.0","id":"query","error":{"name":"HANDLER_ERROR","cause":{"name":"UNKNOWN_ACCOUNT"},"message":"Server error","data":"account \#(accountId) does not exist while viewing"}}"#
            }
        case ("EXPERIMENTAL_protocol_config", _):
            json = Self.protocolConfig
        default:
            throw HTTPError.invalidURL
        }

        let url = URL(string: "https://near.test")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }

    private static let protocolConfig = #"""
    {"jsonrpc":"2.0","id":"EXPERIMENTAL_protocol_config","result":{"runtime_config":{
      "min_gas_purchase_price":"1000000000",
      "storage_amount_per_byte":"10000000000000000000",
      "transaction_costs":{
        "action_receipt_creation_config":{"send_sir":108059500000,"send_not_sir":108059500000,"execution":108059500000},
        "action_creation_config":{
          "transfer_cost":{"send_sir":115123062500,"send_not_sir":115123062500,"execution":115123062500},
          "create_account_cost":{"send_sir":500000000000,"send_not_sir":500000000000,"execution":7200000000000},
          "add_key_cost":{"full_access_cost":{"send_sir":101765125000,"send_not_sir":101765125000,"execution":101765125000}}
        }
      }
    }}}
    """#
}
