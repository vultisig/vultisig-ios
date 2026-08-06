//
//  KaminoLiveAPITests.swift
//  VultisigAppTests
//
//  OPT-IN, and the only Kamino test that touches the network. Everything else in
//  this folder runs against golden vectors captured on 2026-08-04/05 — which is
//  what makes them deterministic, and also what makes them blind: they freeze
//  `api.kamino.finance` at a moment in time. If Kamino reorders an instruction,
//  adds a step, renames a field, changes what a vault's farm is, or stops
//  rewriting an over-sized withdraw to its `u64::MAX` sentinel, every frozen
//  vector still passes and the app breaks in a user's hands.
//
//  So this suite asserts the same claims against the live API. It is skipped
//  unless `KAMINO_LIVE=1` is in the environment, so `make test` and CI never run
//  it — a network test in the gate is a flaky gate.
//
//      TEST_RUNNER_KAMINO_LIVE=1 xcodebuild test \
//        -scheme VultisigApp -destination 'platform=iOS Simulator,name=iPhone 16' \
//        -only-testing:VultisigAppTests/KaminoLiveAPITests
//
//  (`xcodebuild` forwards `TEST_RUNNER_`-prefixed variables to the test process
//  with the prefix stripped; the plain name is honoured too, for a run from a
//  scheme that sets it directly.)
//
//  Two rules this suite is written to, because live balances move:
//
//  1. **Assert shape and invariants, never amounts.** The sampled wallets below
//     were holders on 2026-08-05. They may have exited since. A wallet that no
//     longer holds is a SKIP with its address named — never a silent pass and
//     never a failure, because their balance is not this app's behaviour.
//  2. **Nothing here signs anything.** The API builds unsigned transactions for
//     any address, so every request below is a POST and a decode against wallets
//     we do not control. No key material is involved and no funds can move.
//

import BigInt
@testable import VultisigApp
import XCTest

final class KaminoLiveAPITests: XCTestCase {

    // MARK: - Opt-in gate

    private static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["KAMINO_LIVE", "TEST_RUNNER_KAMINO_LIVE"].contains { environment[$0] == "1" }
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            Self.isEnabled,
            "live Kamino test — set KAMINO_LIVE=1 (or TEST_RUNNER_KAMINO_LIVE=1 under xcodebuild) to run it"
        )
    }

    // MARK: - Vault identity

    /// The registry pins each vault's mints, their decimals and its farm, and
    /// `fetchVaultInfo` refuses a response that disagrees. Those are immutable
    /// properties of a kVault, so this can only fail if the registry is wrong or
    /// the API's account of a vault changed — either of which invalidates every
    /// amount the app scales and every destination it derives.
    ///
    /// The live fields are checked for range rather than value: they legitimately
    /// move, but an APY that arrives as `3.91` instead of `0.0391` is a unit
    /// change, and the app renders it as 391 %.
    func testEveryCuratedVaultStillMatchesThePinnedRegistry() async throws {
        for descriptor in KaminoVaultRegistry.allowList {
            let vault = try await service.fetchVaultInfo(descriptor: descriptor)

            XCTAssertFalse(vault.name.isEmpty, "\(descriptor.fallbackName): empty on-chain name")
            XCTAssertFalse(vault.lookupTable.isEmpty, "\(descriptor.fallbackName): no lookup table")
            XCTAssertGreaterThan(
                vault.minDeposit.baseUnits, 0,
                "\(descriptor.fallbackName): minDepositAmount is not positive"
            )
            XCTAssertGreaterThan(
                vault.minWithdraw.baseUnits, 0,
                "\(descriptor.fallbackName): minWithdrawAmount is not positive"
            )
            XCTAssertTrue(
                vault.apy30d >= 0 && vault.apy30d < 1,
                "\(descriptor.fallbackName): apy30d \(vault.apy30d) is not a fraction — it may have become a percentage"
            )
            XCTAssertGreaterThan(
                vault.tokenPriceUsd, 0,
                "\(descriptor.fallbackName): tokenPrice is not positive"
            )

            note("\(vault.name): apy30d \(vault.apy30d), lookup table \(vault.lookupTable)")
        }
    }

    // MARK: - Deposit

    /// The whole deposit pipeline minus the network's opinion: build → parse →
    /// validate as built → inject the compute budget → validate again with the
    /// fee pinned → read the result back with the offline decoder.
    ///
    /// No balance is required because nothing is simulated here, and that is a
    /// limit worth stating rather than hiding: **no test in this suite simulates
    /// a deposit.** A deposit that executes needs a wallet holding the vault's
    /// underlying token, which none of the sampled addresses is, so the probe
    /// owner can only ever prove the transaction's SHAPE — which is what drifts.
    /// A deposit's execution is the on-device run's to establish.
    func testEveryCuratedVaultStillBuildsADepositThisAppWillValidate() async throws {
        for descriptor in KaminoVaultRegistry.allowList {
            let vault = try await service.fetchVaultInfo(descriptor: descriptor)
            let amount = vault.minDeposit

            let built = try await service.buildDepositTransaction(
                owner: Self.probeOwner,
                vault: descriptor.address,
                amount: amount
            )
            let transaction = try SolanaV0Transaction(base64Transaction: built)

            let intent = KaminoTransactionIntent(
                operation: .deposit(amount),
                vault: vault,
                owner: Self.probeOwner
            )
            try await validator.validate(transaction: transaction, intent: intent)

            let fee = KaminoPriorityFee(
                limit: KaminoComputeBudget.depositUnitLimit(for: vault),
                price: KaminoComputeBudget.fallbackUnitPriceMicroLamports
            )
            let injected = try transaction.injectingComputeBudget(price: fee.price, limit: fee.limit)
            try await validator.validate(
                transaction: injected,
                intent: KaminoTransactionIntent(
                    operation: .deposit(amount),
                    vault: vault,
                    owner: Self.probeOwner,
                    priorityFee: fee
                )
            )

            let decoded = try XCTUnwrap(
                KaminoTransactionDecoder.decode(injected),
                "\(vault.name): the offline decoder could not read back a deposit it had just validated"
            )
            XCTAssertEqual(decoded.operation, .deposit, "\(vault.name): decoded as the wrong operation")
            XCTAssertEqual(decoded.descriptor, descriptor, "\(vault.name): decoded as the wrong vault")
            XCTAssertEqual(decoded.amountBaseUnits, amount.baseUnits, "\(vault.name): decoded a different amount")
            XCTAssertEqual(decoded.priorityFee, fee, "\(vault.name): decoded a different compute budget")
            XCTAssertEqual(
                decoded.strandsWrappedSolRent, descriptor.tokenMint == KaminoVaultRegistry.wrappedSolMint,
                "\(vault.name): the wrapped-SOL rent disclosure disagrees with the vault's own mint"
            )

            note("\(vault.name): deposit \(amount.apiString) → \(transaction.instructions.count) instructions, \(transaction.wireSize) B")
        }
    }

    /// The deposit half of the same defect, and the reason the suite's earlier
    /// claim that "no test here simulates a deposit" was a gap worth closing:
    /// the form advertised `minDepositAmount` and the program refused it with
    /// `DepositAmountBelowMinimum` (custom 7026, `vault_operations.rs:113`).
    /// Steakhouse refuses 100,007 base units and accepts 100,008; Allez refuses
    /// 10,000,009 and accepts 10,000,010.
    ///
    /// This also covers the SOL vault's maximum, which `maxNativeDepositLamports`
    /// measures by preparing a probe deposit of exactly this amount — a probe
    /// below the program's floor made that whole measurement throw.
    ///
    /// Only the minimum is asserted. The probe owner's balance is not this
    /// app's behaviour, so a failure that is *not* the minimum error is a skip.
    func testTheMinimumDepositTheFormAdvertisesActuallyExecutes() async throws {
        for descriptor in KaminoVaultRegistry.allowList {
            let vault = try await service.fetchVaultInfo(descriptor: descriptor)

            let built = try await service.buildDepositTransaction(
                owner: Self.probeOwner,
                vault: descriptor.address,
                amount: vault.minDeposit
            )
            let result = try await solana.simulateTransaction(
                base64Transaction: built,
                replaceRecentBlockhash: true,
                accountAddresses: []
            )
            guard let failure = result.failure else { continue }

            let refusedTheAmount = result.logs.contains { $0.contains("DepositAmountBelowMinimum") }
            XCTAssertFalse(
                refusedTheAmount,
                "\(vault.name): a deposit at the advertised minimum of \(vault.minDeposit.apiString) "
                + "is below the program's floor — \(failure)"
            )
            if !refusedTheAmount {
                note("SKIP \(vault.name): the probe wallet could not fund a minimum deposit — \(failure)")
            }
        }
    }

    // MARK: - Withdraw

    /// The farm-staked withdraw — five instructions on a token vault, six on the
    /// wrapped-SOL one — is the shape every real position is in, and the shape
    /// the app carried as an explicit refusal until it was captured. It is also
    /// the newest code in the feature.
    ///
    /// A request above the wallet's unstaked balance is what makes the API emit
    /// the farms pair, so the amount is chosen from the live position rather than
    /// fixed: `unstaked + 1` for a holder, the vault minimum for a wallet with no
    /// position at all.
    ///
    /// ⚠️ **A withdraw needs a real holder — a position-less wallet cannot stand
    /// in.** The sentinel fires at `requested ≥ balance`, and every amount is
    /// ≥ a zero balance, so the API answers a wallet that holds nothing with
    /// `u64::MAX` and the validator refuses it. That is the rule working, not
    /// drift. A vault whose sampled holders have all exited is therefore a SKIP
    /// with its coverage loss named, never a silent pass.
    func testEveryCuratedVaultStillBuildsAWithdrawThisAppWillValidate() async throws {
        var validated = 0
        for descriptor in KaminoVaultRegistry.allowList {
            let vault = try await service.fetchVaultInfo(descriptor: descriptor)
            guard let holder = try await resolveHolder(for: descriptor) else {
                note("SKIP \(vault.name): none of its sampled wallets still holds a position — withdraw shape uncovered")
                continue
            }
            let owner = holder.owner
            let unstaked = holder.position.unstaked

            // Strictly above the unstaked balance, so the farms pair is required,
            // and clear of the vault's own minimum.
            let shares = KaminoShareAmount(
                baseUnits: max(unstaked.baseUnits + 1, vault.minWithdraw.baseUnits),
                decimals: descriptor.sharesDecimals
            )
            if shares.baseUnits > holder.position.spendable.baseUnits {
                note("SKIP \(vault.name): \(owner) holds too little to ask above its unstaked balance")
                continue
            }

            let request = KaminoWithdrawRequest(shares: shares, unstakedShares: unstaked)
            XCTAssertTrue(
                request.requiresUnstake,
                "\(vault.name): a request above the unstaked balance should need a farm release"
            )

            let built: String
            do {
                built = try await service.buildWithdrawTransaction(
                    owner: owner,
                    vault: descriptor.address,
                    shares: shares
                )
            } catch let skip as XCTSkip {
                // The transport wrapper's own signal. Catching it here would
                // turn an outage into a drift report, which is the failure mode
                // the wrapper exists to prevent.
                throw skip
            } catch {
                // The wallet holds a position and the amount is inside it, so a
                // refusal here is the API changing its mind about a request it
                // answered on 2026-08-05.
                XCTFail("\(vault.name): the API refused a withdraw for holder \(owner): \(error)")
                continue
            }

            let transaction = try SolanaV0Transaction(base64Transaction: built)
            let intent = KaminoTransactionIntent(operation: .withdraw(request), vault: vault, owner: owner)
            try await validator.validate(transaction: transaction, intent: intent)

            let fee = KaminoPriorityFee(
                limit: KaminoComputeBudget.withdrawUnitLimit,
                price: KaminoComputeBudget.fallbackUnitPriceMicroLamports
            )
            let injected = try transaction.injectingComputeBudget(price: fee.price, limit: fee.limit)
            try await validator.validate(
                transaction: injected,
                intent: KaminoTransactionIntent(
                    operation: .withdraw(request),
                    vault: vault,
                    owner: owner,
                    priorityFee: fee
                )
            )

            let decoded = try XCTUnwrap(
                KaminoTransactionDecoder.decode(injected),
                "\(vault.name): the offline decoder could not read back a withdraw it had just validated"
            )
            XCTAssertEqual(decoded.operation, .withdraw, "\(vault.name): decoded as the wrong operation")
            XCTAssertEqual(decoded.descriptor, descriptor, "\(vault.name): decoded as the wrong vault")
            XCTAssertEqual(decoded.amountBaseUnits, shares.baseUnits, "\(vault.name): decoded a different share count")
            XCTAssertFalse(decoded.withdrawsEntirePosition, "\(vault.name): the response carried the sentinel")

            validated += 1
            note(
                "\(vault.name): \(request.requiresUnstake ? "staked" : "short") withdraw for \(owner) → "
                + "\(transaction.instructions.count) instructions, \(transaction.wireSize) B"
            )
        }

        // Otherwise a run where every vault's sampled wallets had exited reports
        // itself green while having validated nothing.
        try XCTSkipIf(validated == 0, "no curated vault had a live holder — the withdraw shape went unchecked")
    }

    /// The regression test for the defect this suite found on its first run, and
    /// the only thing that can keep the fix honest: the floor it clears was
    /// measured against the live chain, not derived from a document.
    ///
    /// The form used to offer `state.minWithdrawAmount` read as SHARE base
    /// units. A withdraw at exactly that figure does not execute — the kVaults
    /// program throws `WithdrawAmountBelowMinimum` (custom 7004,
    /// `vault_operations.rs:325`).
    ///
    /// Measured 2026-08-06 by binary search over the live simulation, on both
    /// shapes (the farm-staked path and the short one, which share the boundary,
    /// so it belongs to the vault withdraw rather than the farm release):
    ///
    /// | vault | published `minWithdrawAmount` | smallest that executes |
    /// |---|---|---|
    /// | Steakhouse USDC | 1000 | **1899** share base units |
    /// | Allez SOL | 1000 | **1862** share base units |
    ///
    /// Both floors are the smallest share count worth strictly more than 2000
    /// TOKEN base units at the live rate — 1899 × 1.05385 = 2001.3, and one unit
    /// below lands on 2000.2; 1862 × 0.00107518 = 2001.98 lamports against
    /// 2000.9. So the published figure is not a share count at all, and the
    /// program's floor is not the published figure either.
    ///
    /// Nothing was ever at risk: the preparer's post-injection simulation
    /// requires `err == nil`, so an amount in the band between the two refused
    /// before a signer saw it. What broke was the form — it advertised a
    /// minimum, accepted it, and then failed at verify with a simulation error.
    ///
    /// `KaminoService.effectiveMinimumWithdraw` now derives the figure from the
    /// published TOKEN amount with a margin above the observed ×2, so this
    /// passes. It fails again if Kamino moves the floor, or if the margin is
    /// ever trimmed to the measurement — which is the point of running it
    /// against the chain rather than against the arithmetic.
    func testTheMinimumWithdrawTheFormAdvertisesActuallyExecutes() async throws {
        var checked = 0
        for descriptor in KaminoVaultRegistry.allowList {
            let vault = try await service.fetchVaultInfo(descriptor: descriptor)
            guard let holder = try await resolveHolder(for: descriptor),
                  vault.minWithdraw.baseUnits <= holder.position.spendable.baseUnits
            else { continue }

            let built = try await executableWithdraw(
                owner: holder.owner,
                descriptor: descriptor,
                shares: vault.minWithdraw
            )
            let result = try await solana.simulateTransaction(
                base64Transaction: built,
                replaceRecentBlockhash: true,
                accountAddresses: []
            )
            XCTAssertNil(
                result.failure,
                "\(vault.name): a withdraw at the advertised minimum of \(vault.minWithdraw.apiString) shares "
                + "does not execute — \(result.failure ?? "")"
            )
            checked += 1
        }
        try XCTSkipIf(checked == 0, "no sampled wallet holds enough to withdraw a vault minimum")
    }

    /// The step-8 discovery, re-asserted live: **the instruction sequence is
    /// conditional on the AMOUNT, not on whether the vault has a farm.** At or
    /// below the wallet's unstaked balance the API builds the short shape with no
    /// farms instructions; one base unit above it, the pair appears and releases
    /// exactly the shortfall.
    ///
    /// This needs a *mixed* holder — shares both staked and unstaked — and it is
    /// the only route to the short shape at all. Every deposit auto-stakes, so a
    /// position this app creates always has `unstaked == 0` and can never produce
    /// it. A borrowed wallet is not a convenience here; it is the only coverage
    /// that path can have short of leaving shares unstaked on purpose.
    func testTheWithdrawShapeStillTurnsOnTheAmountAndNotTheFarm() async throws {
        let descriptor = KaminoVaultRegistry.steakhouseUSDC
        let vault = try await service.fetchVaultInfo(descriptor: descriptor)

        guard let holder = try await resolveMixedHolder(for: descriptor) else {
            throw XCTSkip(
                "no sampled wallet still holds a MIXED position in \(descriptor.fallbackName) "
                + "(candidates: \(Self.mixedHolders.joined(separator: ", ")))"
            )
        }
        let unstaked = holder.position.unstaked

        // At the unstaked balance exactly: no farm release, and the intent says
        // so — which makes the farms pair FORBIDDEN, so a response carrying one
        // is refused rather than tolerated.
        let withinRequest = KaminoWithdrawRequest(shares: unstaked, unstakedShares: unstaked)
        XCTAssertFalse(withinRequest.requiresUnstake, "a request at the unstaked balance needs no release")
        let within = try SolanaV0Transaction(
            base64Transaction: try await service.buildWithdrawTransaction(
                owner: holder.owner,
                vault: descriptor.address,
                shares: unstaked
            )
        )
        try await validator.validate(
            transaction: within,
            intent: KaminoTransactionIntent(operation: .withdraw(withinRequest), vault: vault, owner: holder.owner)
        )

        // One base unit above it: the pair appears, and the unstake is the
        // shortfall — exactly one base unit, WAD-scaled. The validator pins that
        // argument, so this passing IS the assertion on the amount.
        let straddling = KaminoShareAmount(
            baseUnits: unstaked.baseUnits + 1,
            decimals: descriptor.sharesDecimals
        )
        let straddlingRequest = KaminoWithdrawRequest(shares: straddling, unstakedShares: unstaked)
        XCTAssertEqual(straddlingRequest.unstakeShares.baseUnits, 1, "the shortfall should be one base unit")
        let above = try SolanaV0Transaction(
            base64Transaction: try await service.buildWithdrawTransaction(
                owner: holder.owner,
                vault: descriptor.address,
                shares: straddling
            )
        )
        try await validator.validate(
            transaction: above,
            intent: KaminoTransactionIntent(operation: .withdraw(straddlingRequest), vault: vault, owner: holder.owner)
        )

        XCTAssertGreaterThan(
            above.instructions.count, within.instructions.count,
            "one base unit above the unstaked balance should add the farms pair, but the shapes match"
        )

        note(
            "\(vault.name) \(holder.owner): at unstaked \(within.instructions.count) instructions, "
            + "one base unit above \(above.instructions.count)"
        )
    }

    // MARK: - The sentinel boundary

    /// The fund-safety boundary of the whole feature, re-measured live.
    ///
    /// A withdraw naming at or above the wallet's balance is silently rewritten
    /// by the API to `u64::MAX` — *withdraw everything*. `spendable` is the
    /// largest amount strictly below the balance and is what the app's maximum
    /// sends; the control is the truncated total, which produces the sentinel
    /// whenever the balance was exactly representable at the mint's scale.
    ///
    /// A failure on the control half is not a regression in this app — it means
    /// Kamino changed how an over-sized withdraw is handled, and the `spendable`
    /// dust rule (and the ≤ 1 base unit it strands) should be revisited.
    func testTheWithdrawEverythingSentinelStillFiresAtTheExactBalance() async throws {
        let descriptor = KaminoVaultRegistry.steakhouseUSDC
        guard let holder = try await resolveHolder(for: descriptor) else {
            throw XCTSkip("no sampled wallet still holds a position in \(descriptor.fallbackName)")
        }
        let position = holder.position

        let atSpendable = try await decodedWithdraw(
            owner: holder.owner,
            descriptor: descriptor,
            shares: position.spendable
        )
        XCTAssertFalse(
            atSpendable.decoded.withdrawsEntirePosition,
            "the app's own maximum produced the sentinel — the strictly-below rule no longer holds"
        )
        XCTAssertEqual(
            atSpendable.decoded.amountBaseUnits, position.spendable.baseUnits,
            "the built transaction names a different share count than was requested"
        )

        // The truncation was exact when `spendable` had to step back a base unit;
        // only then is the truncated total the balance itself.
        let truncationWasExact = position.spendable.baseUnits == position.total.baseUnits - 1
        let atTotal = try await decodedWithdraw(
            owner: holder.owner,
            descriptor: descriptor,
            shares: position.total
        )
        if truncationWasExact {
            XCTAssertTrue(
                atTotal.decoded.withdrawsEntirePosition,
                "requesting the exact balance no longer produces the sentinel — the maximum rule can be relaxed"
            )
        } else {
            XCTAssertEqual(
                atTotal.decoded.amountBaseUnits, position.total.baseUnits,
                "a request strictly below the balance was rewritten anyway"
            )
        }

        note(
            "\(descriptor.fallbackName) \(holder.owner): total \(position.total.apiString), "
            + "spendable \(position.spendable.apiString), exactly representable: \(truncationWasExact)"
        )
    }

    /// `stakedShares + unstakedShares == totalShares` held in all 80 sampled
    /// positions at the API's own precision, and the app's "unaccounted shares"
    /// guard rests on it: a total that exceeds the parts it is made of means the
    /// position read is missing something, and the withdraw form refuses rather
    /// than sizing a transaction from it.
    func testEverySampledPositionStillAccountsForItsTotal() async throws {
        var checked = 0
        for descriptor in KaminoVaultRegistry.allowList {
            for owner in Self.holders[descriptor.address] ?? [] {
                guard let response = try await position(of: owner, in: descriptor) else { continue }
                let parsed = try XCTUnwrap(
                    KaminoSharePosition(response: response, shareDecimals: descriptor.sharesDecimals),
                    "\(owner): /positions returned a value this app cannot parse: \(response)"
                )
                XCTAssertTrue(
                    parsed.accountsForItsTotal,
                    "\(owner) in \(descriptor.fallbackName): staked + unstaked no longer equals the total"
                )
                // `total` here is the REPORTED balance truncated to the mint's
                // scale, not the balance itself, so equality is the ordinary
                // case: `spendable` only steps back a base unit when the
                // truncation was exact. What must never happen is exceeding it.
                XCTAssertLessThanOrEqual(
                    parsed.spendable.baseUnits, parsed.total.baseUnits,
                    "\(owner): the spendable maximum exceeds the balance it was derived from"
                )
                checked += 1
            }
        }
        try XCTSkipIf(checked == 0, "none of the sampled wallets still holds a position in any curated vault")
        note("checked \(checked) live positions")
    }

    // MARK: - Execution

    /// The compute limit for a withdraw was raised 220,000 → 400,000 because
    /// every farm-staked shape aborted on the CU meter below it (283k–309k
    /// measured). That headroom is what this asserts, against a transaction the
    /// network actually ran.
    ///
    /// `replaceRecentBlockhash` lets the node substitute a live blockhash, so the
    /// result is about execution rather than about how old the build is.
    func testAStakedWithdrawStillExecutesInsideItsComputeLimit() async throws {
        let descriptor = KaminoVaultRegistry.steakhouseUSDC
        let vault = try await service.fetchVaultInfo(descriptor: descriptor)
        guard let holder = try await resolveHolder(for: descriptor),
              holder.position.staked.baseUnits > 0
        else {
            throw XCTSkip("no sampled wallet still holds STAKED shares in \(descriptor.fallbackName)")
        }

        // Comfortably clear of the advertised minimum, because that minimum does
        // not execute — see `testTheMinimumWithdrawTheFormAdvertisesActuallyExecutes`.
        // At the advertised figure this measures the program's minimum check
        // rather than the compute the withdraw needs.
        let shares = KaminoShareAmount(
            baseUnits: max(holder.position.unstaked.baseUnits + 1, vault.minWithdraw.baseUnits * 4),
            decimals: descriptor.sharesDecimals
        )
        try XCTSkipIf(
            shares.baseUnits > holder.position.spendable.baseUnits,
            "\(holder.owner) holds too little to ask above its unstaked balance"
        )

        let built = try await executableWithdraw(
            owner: holder.owner,
            descriptor: descriptor,
            shares: shares
        )
        let injected = try SolanaV0Transaction(base64Transaction: built)
            .injectingComputeBudget(
                price: KaminoComputeBudget.fallbackUnitPriceMicroLamports,
                limit: KaminoComputeBudget.withdrawUnitLimit
            )

        let result = try await solana.simulateTransaction(
            base64Transaction: injected.base64EncodedTransaction,
            replaceRecentBlockhash: true,
            accountAddresses: []
        )
        XCTAssertNil(result.failure, "the staked withdraw no longer executes: \(result.failure ?? "")")

        let consumed = try XCTUnwrap(result.unitsConsumed, "the node reported no compute usage")
        XCTAssertLessThan(
            consumed, UInt64(KaminoComputeBudget.withdrawUnitLimit),
            "a staked withdraw now consumes \(consumed) CU against a \(KaminoComputeBudget.withdrawUnitLimit) limit"
        )

        note("staked withdraw consumed \(consumed) CU of \(KaminoComputeBudget.withdrawUnitLimit)")
    }

    // MARK: - Live collaborators
    //
    // Both are wrapped so a dropped connection or a rate limit SKIPS the test
    // instead of failing it. A live suite that cries drift when the Wi-Fi
    // hiccups is ignored by its second false alarm — and these endpoints do rate
    // limit, which is exactly what a burst of builds from one machine looks like.

    private let service = SkipOnTransportFailure(wrapping: KaminoService())

    /// Built with a resolver that reports no override rather than
    /// `SolanaService.shared`, so the test drives the default Vultisig RPC proxy
    /// and never depends on whatever custom endpoint the host app has stored.
    private let solana = SkipOnTransportFailure(wrapping: SolanaService(resolver: NoCustomRPC()))

    private var validator: KaminoTransactionValidator {
        KaminoTransactionValidator(lookupTableSource: solana)
    }

    // MARK: - Sampled wallets
    //
    // Holders as of 2026-08-05, from the capture scripts in the wiki workstream
    // (`fixtures/find_staked_holder.py`, `find_mixed.py`, `probe_boundary.py`).
    // They are inputs, not expectations — see the header.

    /// A wallet with no Kamino position, used where only the built transaction's
    /// shape matters. It is the fee payer of the captured deposit vectors.
    private static let probeOwner = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"

    private static let mixedHolders = [
        "DhCrkyWYGQayd4QNUDdLyvrALLmrJqTUHPGoA98pX2YU",
        "BXQ94NosJk3pnT9s6gNMx2WYbMSNnsJJ22zpRmbRZtMm",
        "8dQH1VxZnD6N8iigY5EsjXbFyoETppzFEmVUfS7XKhMp"
    ]

    private static let holders: [String: [String]] = [
        KaminoVaultRegistry.steakhouseUSDC.address: [
            // Wholly staked — the position every real user of this feature is in.
            "6BTaMq25LcNDTVhheUe9UyvwWgayqFv77njymVnG8SNy"
        ] + mixedHolders + [
            // Wholly unstaked — the only wallets that exercise the short shape.
            "HXvxyS3AuRzt8eLpTpD3dhz4vKNkNino9eYFCDqrNMan"
        ],
        KaminoVaultRegistry.allezSOL.address: [
            "CHFeSGER1nXFUtvdAVb49rLHTgvvuxEXmeTG3GBtgKzF"
        ],
        // Sampled 2026-08-06, the same way the Steakhouse holder was found:
        // recent signers on the vault account, then asking the API what each
        // holds. Four, so the withdraw path keeps coverage as wallets exit.
        KaminoVaultRegistry.rwaUSDC.address: [
            "FoHks2gGvxVR6fB7v8g6UgscwRtwP1NeNV8HYkH6nmoU",
            "5SvXwNY6smxQnHmD3N1Cs2MqHfgNwH2H9ArN5TWcf7Uy",
            "8tqVF258kyBpZWNH4mhvKBaWg6hiPBx7cwUqWoFAidgb",
            "v6so71BNfg2oPgw6ErkY3T93iVBDxemqKyAQD9hJeAQ"
        ]
    ]

    // MARK: - Helpers

    private struct LiveHolder {
        let owner: String
        let position: KaminoSharePosition
    }

    private func position(
        of owner: String,
        in descriptor: KaminoVaultDescriptor
    ) async throws -> KaminoUserPositionResponse? {
        try await service.fetchPositions(owner: owner)
            .first { $0.vaultAddress == descriptor.address }
    }

    /// The first sampled wallet that still holds anything in `descriptor`.
    private func resolveHolder(for descriptor: KaminoVaultDescriptor) async throws -> LiveHolder? {
        try await resolveHolder(for: descriptor, matching: { $0.total.baseUnits > 0 })
    }

    /// The first sampled wallet whose position is still *mixed* — shares in the
    /// farm and shares in its own token account at the same time.
    private func resolveMixedHolder(for descriptor: KaminoVaultDescriptor) async throws -> LiveHolder? {
        try await resolveHolder(for: descriptor) { position in
            position.staked.baseUnits > 0 && position.unstaked.baseUnits > 0
        }
    }

    /// `nil` means every sampled wallet answered and none of them matches — a
    /// coverage loss, which each caller turns into a skip.
    ///
    /// It deliberately does NOT mean "the lookup failed". A `try?` here would
    /// read a decode failure, a 4xx, a registry mismatch or the transport
    /// wrapper's own skip as "no holder", and the tests downstream would go
    /// quiet at precisely the moment they have something to report. Only an
    /// answered request that named no position for this vault continues.
    private func resolveHolder(
        for descriptor: KaminoVaultDescriptor,
        matching predicate: (KaminoSharePosition) -> Bool
    ) async throws -> LiveHolder? {
        for owner in Self.holders[descriptor.address] ?? [] {
            guard let response = try await position(of: owner, in: descriptor) else { continue }
            guard let parsed = KaminoSharePosition(
                response: response,
                shareDecimals: descriptor.sharesDecimals
            ) else {
                XCTFail("\(owner): /positions returned a value this app cannot parse: \(response)")
                continue
            }
            if predicate(parsed) {
                return LiveHolder(owner: owner, position: parsed)
            }
        }
        return nil
    }

    private func decodedWithdraw(
        owner: String,
        descriptor: KaminoVaultDescriptor,
        shares: KaminoShareAmount
    ) async throws -> (base64: String, decoded: KaminoDecodedTransaction) {
        let built = try await service.buildWithdrawTransaction(
            owner: owner,
            vault: descriptor.address,
            shares: shares
        )
        let transaction = try SolanaV0Transaction(base64Transaction: built)
        let decoded = try XCTUnwrap(
            KaminoTransactionDecoder.decode(transaction),
            "the offline decoder could not read a withdraw of \(shares.apiString) for \(owner)"
        )
        return (built, decoded)
    }

    /// Builds a withdraw and refuses to hand it back unless it names the amount
    /// that was asked for.
    ///
    /// Every test that goes on to SIMULATE has to come through here. A balance
    /// that moved between the read and the build turns the request into the
    /// `u64::MAX` sentinel, and *withdraw everything* executes perfectly well —
    /// so a simulation of unchecked bytes can report success for a transaction
    /// that is not the one under test. That would make the minimum test say the
    /// advertised minimum executes, on a transaction that withdrew the lot.
    private func executableWithdraw(
        owner: String,
        descriptor: KaminoVaultDescriptor,
        shares: KaminoShareAmount
    ) async throws -> String {
        let built = try await decodedWithdraw(owner: owner, descriptor: descriptor, shares: shares)
        XCTAssertFalse(
            built.decoded.withdrawsEntirePosition,
            "\(owner): the API rewrote a \(shares.apiString)-share request to the withdraw-everything sentinel"
        )
        XCTAssertEqual(
            built.decoded.amountBaseUnits, shares.baseUnits,
            "\(owner): the built transaction names a different share count than was requested"
        )
        return built.base64
    }

    /// The measurements are the point of a live run, so they go to the console a
    /// human is watching rather than into a log this suite's reader never opens.
    private func note(_ message: String) {
        print("[kamino-live] \(message)")
    }
}

// MARK: - Test doubles

/// Reports no custom RPC override, so the service resolves its default host.
private struct NoCustomRPC: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

/// Forwards every call, turning a transport failure into a SKIP.
///
/// The distinction it draws is the one that decides whether this suite is worth
/// reading: a dropped connection, a timeout, a 429 or a 5xx is the API being
/// unreachable, which says nothing about whether it still builds the
/// transactions this app validates. Everything else — a 4xx that is not a rate
/// limit, a decode failure, a value this app refused — is a claim about the
/// response, and stays a failure.
private struct SkipOnTransportFailure<Wrapped> {

    let wrapped: Wrapped

    init(wrapping wrapped: Wrapped) {
        self.wrapped = wrapped
    }

    func skipping<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error where Self.isTransport(error) {
            throw XCTSkip("the live API was unreachable, so nothing was measured — \(error)")
        }
    }

    private static func isTransport(_ error: Error) -> Bool {
        switch error {
        case let error as HTTPError:
            switch error {
            case .timeout, .networkError:
                return true
            case .statusCode(let status, _):
                return status == 429 || status >= 500
            default:
                return false
            }
        case let error as KaminoServiceError:
            guard case .api(let status, _, _) = error else { return false }
            return status == 429 || status >= 500
        case let error as URLError:
            return [.networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost]
                .contains(error.code)
        default:
            return false
        }
    }
}

extension SkipOnTransportFailure: KaminoServiceProtocol where Wrapped: KaminoServiceProtocol {

    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse {
        try await skipping { try await wrapped.fetchVaultState(address: address) }
    }

    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse {
        try await skipping { try await wrapped.fetchVaultMetrics(address: address) }
    }

    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo {
        try await skipping { try await wrapped.fetchVaultInfo(descriptor: descriptor) }
    }

    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse] {
        try await skipping { try await wrapped.fetchPositions(owner: owner) }
    }

    func fetchPnl(owner: String, vault: String) async throws -> KaminoPnlResponse {
        try await skipping { try await wrapped.fetchPnl(owner: owner, vault: vault) }
    }

    func buildDepositTransaction(
        owner: String,
        vault: String,
        amount: KaminoTokenAmount
    ) async throws -> String {
        try await skipping {
            try await wrapped.buildDepositTransaction(owner: owner, vault: vault, amount: amount)
        }
    }

    func buildWithdrawTransaction(
        owner: String,
        vault: String,
        shares: KaminoShareAmount
    ) async throws -> String {
        try await skipping {
            try await wrapped.buildWithdrawTransaction(owner: owner, vault: vault, shares: shares)
        }
    }
}

extension SkipOnTransportFailure: SolanaAddressLookupTableFetching
where Wrapped: SolanaAddressLookupTableFetching {

    func fetchAddressLookupTables(addresses: [String]) async throws -> [String: [String]] {
        try await skipping { try await wrapped.fetchAddressLookupTables(addresses: addresses) }
    }
}

extension SkipOnTransportFailure where Wrapped == SolanaService {

    func simulateTransaction(
        base64Transaction: String,
        replaceRecentBlockhash: Bool,
        accountAddresses: [String]
    ) async throws -> SolanaSimulationResult {
        try await skipping {
            try await wrapped.simulateTransaction(
                base64Transaction: base64Transaction,
                replaceRecentBlockhash: replaceRecentBlockhash,
                accountAddresses: accountAddresses
            )
        }
    }
}
