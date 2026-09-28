import XCTest
@testable import VultisigApp

@MainActor
final class FunctionReviewValidatorTests: XCTestCase {
    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(storeToken)
        storeToken = nil
    }

    func testLoadsAndIndexesValidatorsThroughInjectedService() async throws {
        let service = ValidatorServiceStub()
        service.validators = [validator("First"), validator("Latest")]
        let model = FunctionTransactionVerifyViewModel(stakingService: service)

        await model.loadValidators(transaction: try transaction(staking: true))

        XCTAssertEqual(service.chains, [.gaiaChain])
        XCTAssertEqual(model.validatorsByAddress, ["cosmosvaloper1example": validator("Latest")])
    }

    func testNonStakingReviewDoesNotFetchValidators() async throws {
        let service = ValidatorServiceStub()
        let model = FunctionTransactionVerifyViewModel(stakingService: service)

        await model.loadValidators(transaction: try transaction(staking: false))

        XCTAssertTrue(service.chains.isEmpty)
        XCTAssertTrue(model.validatorsByAddress.isEmpty)
    }

    func testFailedReloadLeavesAddressFallback() async throws {
        let service = ValidatorServiceStub()
        service.validators = [validator("Validator")]
        let model = FunctionTransactionVerifyViewModel(stakingService: service)
        let transaction = try transaction(staking: true)
        await model.loadValidators(transaction: transaction)
        XCTAssertFalse(model.validatorsByAddress.isEmpty)

        service.shouldFail = true
        await model.loadValidators(transaction: transaction)

        XCTAssertTrue(model.validatorsByAddress.isEmpty)
        XCTAssertEqual(CosmosStakingValidatorRows.resolve("cosmosvaloper1example", in: model.validatorsByAddress), "cosmosva…mple")
    }

    private func transaction(staking: Bool) throws -> SendTransaction {
        let model = SendFormFixture.make(coin: SendFormFixture.makeATOM()) {
            $0.toAddress = "cosmos1recipient"
            $0.amount = "1"
        }
        let transaction = try model.makeTransaction()
        guard staking else { return transaction }
        return transaction.copy(cosmosStakingPayload: .set(.delegate(
            validator: "cosmosvaloper1example", denom: "uatom", amount: "1000000"
        )))
    }

    private func validator(_ moniker: String) -> CosmosValidator {
        CosmosValidator(
            operatorAddress: "cosmosvaloper1example", moniker: moniker,
            commission: Decimal(string: "0.0499")!, jailed: false, status: .bonded, votingPower: 1
        )
    }
}

// swiftlint:disable async_without_await unused_parameter
private final class ValidatorServiceStub: CosmosStakingServiceProtocol {
    var validators: [CosmosValidator] = []
    var chains: [Chain] = []
    var shouldFail = false

    func fetchValidators(chain: Chain) async throws -> [CosmosValidator] {
        chains.append(chain)
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return validators
    }

    func fetchDelegations(chain: Chain, address: String) async throws -> [CosmosDelegation] { [] }
    func fetchUnbondingDelegations(chain: Chain, address: String) async throws -> [CosmosUnbondingDelegation] { [] }
    func fetchDelegatorRewards(chain: Chain, address: String) async throws -> CosmosDelegatorRewards {
        CosmosDelegatorRewards(rewards: [], total: [])
    }
    func fetchRedelegations(chain: Chain, address: String) async throws -> [CosmosRedelegationEntry] { [] }
}
// swiftlint:enable async_without_await unused_parameter
