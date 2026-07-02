//
//  InitiatorAmountFiatTests.swift
//  VultisigAppTests
//
//  Pins the initiating device's amount fiat, the counterpart of
//  `JoinKeysignAmountFiatTests`: the send verify header
//  (`SendCryptoVerifyViewModel.amountFiat`) and the keysign hero
//  (`KeysignViewModel.heroContent`, via the shared
//  `BlockaidSimulationInfo.heroContent(title:vaultCoins:)`). Both must share
//  the co-sign path's price source and empty-on-edge-case semantics — a fiat
//  string only for a priced, non-zero amount; empty/nil otherwise, never a
//  misleading "$0.00". Display-only: nothing here affects signing bytes.
//

@testable import VultisigApp
import BigInt
import VultisigCommonData
import XCTest

@MainActor
final class InitiatorAmountFiatTests: XCTestCase {

    // MARK: - Send verify header (SendCryptoVerifyViewModel.amountFiat)

    func testSendVerifyAmountFiatUsesCoinPriceAndAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        // 3 ETH at $2 = $6.
        let vm = makeVerifyViewModel(coin: coin, amount: "3")

        let fiat = vm.amountFiat
        XCTAssertFalse(fiat.isEmpty, "A seeded rate should produce a fiat string")
        XCTAssertTrue(fiat.contains("6"), "3 ETH at $2 should render as 6, got \(fiat)")
    }

    func testSendVerifyAmountFiatEmptyWithoutRate() {
        // Unique ticker → unique priceProviderId that nothing seeds a rate for.
        let coin = makeCoin(.ethereum, ticker: "NORATESENDZZ", decimals: 18, isNative: true)
        let vm = makeVerifyViewModel(coin: coin, amount: "1")
        XCTAssertEqual(vm.amountFiat, "", "No rate → empty, never a misleading $0.00")
    }

    func testSendVerifyAmountFiatEmptyForZeroAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        let vm = makeVerifyViewModel(coin: coin, amount: "0")
        XCTAssertEqual(vm.amountFiat, "", "A zero-value send maps to no meaningful fiat")
    }

    func testSendVerifyAmountFiatEmptyForSubCentFiat() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        // 0.001 ETH at $2 = $0.002 — the 2-decimal fiat formatter rounds down,
        // so this must stay empty rather than render "$0.00". The amount is a
        // user-typed string parsed with the device locale, so build it with
        // the current locale's decimal separator.
        let separator = Locale.current.decimalSeparator ?? "."
        let vm = makeVerifyViewModel(coin: coin, amount: "0\(separator)001")
        XCTAssertEqual(vm.amountFiat, "", "A sub-cent fiat value must not render as $0.00")
    }

    // MARK: - Initiator keysign hero (KeysignViewModel.heroContent)

    func testInitiatorHeroSendResolvesFiatAgainstVaultCoins() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: eth)
        let vm = makeKeysignViewModel(vaultCoins: [eth])
        // 3 ETH at $2 = $6.
        vm.blockaidSimulation = .transfer(
            fromCoin: simCoin(ticker: "ETH", decimals: 18),
            fromAmount: BigInt("3000000000000000000")
        )

        guard case .send(_, let coin) = vm.heroContent else {
            return XCTFail("A transfer simulation should produce a send hero")
        }
        XCTAssertNotNil(coin.fiat, "A vault-held, priced coin should resolve hero fiat")
        XCTAssertTrue(coin.fiat?.contains("6") == true, "3 ETH at $2 should render as 6, got \(coin.fiat ?? "nil")")
    }

    func testInitiatorHeroSwapResolvesFiatForBothRows() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: "0xusdc")
        setPrice(2.0, for: eth)
        setPrice(1.0, for: usdc)
        let vm = makeKeysignViewModel(vaultCoins: [eth, usdc])
        // 1 ETH at $2 = $2 → 5 USDC at $1 = $5. The mixed-case simulation
        // address must still match the vault's lowercase contract address.
        vm.blockaidSimulation = .swap(
            fromCoin: simCoin(ticker: "ETH", decimals: 18),
            toCoin: simCoin(address: "0xUSDC", ticker: "USDC", decimals: 6),
            fromAmount: BigInt("1000000000000000000"),
            toAmount: BigInt("5000000")
        )

        guard case .swap(_, let from, let to) = vm.heroContent else {
            return XCTFail("A swap simulation should produce a swap hero")
        }
        XCTAssertTrue(from.fiat?.contains("2") == true, "1 ETH at $2 should render as 2, got \(from.fiat ?? "nil")")
        XCTAssertTrue(to.fiat?.contains("5") == true, "5 USDC at $1 should render as 5, got \(to.fiat ?? "nil")")
    }

    func testInitiatorHeroFiatNilWhenCoinNotInVault() {
        let vm = makeKeysignViewModel(vaultCoins: [])
        vm.blockaidSimulation = .transfer(
            fromCoin: simCoin(ticker: "ETH", decimals: 18),
            fromAmount: BigInt("1000000000000000000")
        )

        guard case .send(_, let coin) = vm.heroContent else {
            return XCTFail("A transfer simulation should produce a send hero")
        }
        XCTAssertNil(coin.fiat, "No vault match → the hero omits the fiat sub-line")
    }

    func testInitiatorHeroFiatNilWithoutRate() {
        let coin = makeCoin(.ethereum, ticker: "NORATEHEROZZ", decimals: 18, isNative: true)
        let vm = makeKeysignViewModel(vaultCoins: [coin])
        vm.blockaidSimulation = .transfer(
            fromCoin: simCoin(ticker: "NORATEHEROZZ", decimals: 18),
            fromAmount: BigInt("1000000000000000000")
        )

        guard case .send(_, let hero) = vm.heroContent else {
            return XCTFail("A transfer simulation should produce a send hero")
        }
        XCTAssertNil(hero.fiat, "No rate → the hero omits the fiat sub-line, never $0.00")
    }

    func testInitiatorHeroSolNativeSentinelResolvesFiat() {
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        setPrice(3.0, for: sol)
        let vm = makeKeysignViewModel(vaultCoins: [sol])
        // The Blockaid parser encodes native SOL with the wrapped-SOL mint
        // sentinel, not an empty address — it must still match the vault's
        // native SOL coin. 2 SOL at $3 = $6.
        vm.blockaidSimulation = .transfer(
            fromCoin: simCoin(
                chain: .solana,
                address: BlockaidSimulationParser.wrappedSolMint,
                ticker: "SOL",
                decimals: 9
            ),
            fromAmount: BigInt("2000000000")
        )

        guard case .send(_, let coin) = vm.heroContent else {
            return XCTFail("A transfer simulation should produce a send hero")
        }
        XCTAssertNotNil(coin.fiat, "The wrapped-SOL sentinel should resolve the vault's native SOL")
        XCTAssertTrue(coin.fiat?.contains("6") == true, "2 SOL at $3 should render as 6, got \(coin.fiat ?? "nil")")
    }

    func testInitiatorHeroFiatNilForZeroAmount() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: eth)
        let vm = makeKeysignViewModel(vaultCoins: [eth])
        vm.blockaidSimulation = .transfer(
            fromCoin: simCoin(ticker: "ETH", decimals: 18),
            fromAmount: .zero
        )

        guard case .send(_, let coin) = vm.heroContent else {
            return XCTFail("A transfer simulation should produce a send hero")
        }
        XCTAssertNil(coin.fiat, "A zero simulated amount maps to no meaningful fiat")
    }

    // MARK: - Helpers

    private func makeKeysignViewModel(vaultCoins: [Coin]) -> KeysignViewModel {
        let vm = KeysignViewModel()
        vm.vault = makeVault(coins: vaultCoins)
        return vm
    }

    private func makeVerifyViewModel(coin: Coin, amount: String) -> SendCryptoVerifyViewModel {
        SendCryptoVerifyViewModel(
            transaction: makeTransaction(coin: coin, amount: amount),
            interactor: MockSendInteractor()
        )
    }

    private func makeTransaction(coin: Coin, amount: String) -> SendTransaction {
        SendTransaction(
            coin: coin,
            vault: makeVault(coins: [coin]),
            fromAddress: coin.address,
            toAddress: "0x0000000000000000000000000000000000000001",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
    }

    private func makeVault(coins: [Coin]) -> Vault {
        let vault = Vault(name: "initiator-fiat-test-vault")
        vault.coins = coins
        return vault
    }

    private func simCoin(chain: Chain = .ethereum, address: String? = nil, ticker: String, decimals: Int) -> BlockaidSimulationCoin {
        BlockaidSimulationCoin(
            chain: chain,
            address: address,
            ticker: ticker,
            logo: "logo",
            decimals: decimals
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, contract: String = "") -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "test-\(ticker)", hexPublicKey: "")
    }

    private func setPrice(_ value: Double, for coin: Coin) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        try? RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
        ])
    }
}
