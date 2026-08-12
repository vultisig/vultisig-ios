//
//  LimitSwapBodyView.swift
//  VultisigApp
//

import SwiftUI

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. **Uniswap-style flat layout**: the asset
/// swap form (Sell + swap button + Buy) on top, the price card ("When 1 <sell>
/// is worth <price> <buy>" + Market/+1%/+5%/+10% pills) below it, then the
/// expiry card, then the inline notices, with the Place-Order CTA pinned to the
/// bottom — the user picks what they're trading before stating the condition it
/// executes under. Every input is visible at once, so the price and the amount
/// it applies to are never hidden behind a chevron.
///
/// The price chart is the one collapsible thing here, and it does not breach
/// that rule: it is an optional *way* of choosing a price the field and the
/// preset pills can already set, both of which stay on screen. It starts
/// collapsed and, while collapsed, is not fetched at all.
///
/// All business logic lives in `LimitSwapFormViewModel`; this view is
/// declarative. The price field always edits `draft.targetPrice` in the target
/// asset's terms (the value the signed memo's LIM is derived from) — the $/asset
/// toggle only changes which representation is emphasized, never how the price is
/// stored, so the memo math is never at risk.
struct LimitSwapBodyView: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin

    @State private var sourceAmountText: String = ""
    /// Buy-side amount text. Editable; when the user types here the Sell side
    /// becomes the derived one (see `LimitAmountDriver`).
    @State private var buyAmountText: String = ""
    /// Absorbs the one echo of a programmatic write to `buyAmountText`, the same
    /// guard the USD mirror uses — without it, settling the field to
    /// the re-derived `expectedBuyAmount` would read as a fresh user edit and
    /// re-enter `buyAmountChanged` with a rounded figure.
    @State private var lastSyncedBuyText: String?
    /// Echo guard for programmatic writes to `sourceAmountText` — the Sell field
    /// is now written to as well as read, whenever a Buy-driven entry moves the
    /// deposit.
    @State private var lastSyncedSellText: String?
    @State private var priceText: String = ""
    /// USD-mode mirror of `priceText`. Editable in USD mode; kept in sync with
    /// `draft.targetPrice` (× the target USD rate) so switching modes shows the
    /// right value. The canonical price stays `draft.targetPrice` (asset terms).
    @State private var usdText: String = ""
    /// The last value written to `usdText` PROGRAMMATICALLY (by `syncUsdText`).
    /// `onChange(usdText)` absorbs this one echo so a preset/rate/mode redraw of
    /// the USD field can't round-trip through the 2-dp USD display and mutate the
    /// canonical asset-terms price. `nil` once absorbed → the next change is a
    /// genuine user edit.
    @State private var lastSyncedUsdText: String?
    /// Mirrors the market swap: reset to `true` on a manual amount edit so the
    /// shared `SwapPercentageButtons` clears its selected-pill highlight.
    @State private var showAllPercentageButtons = true
    /// Drives the single keyboard accessory below — see `LimitFocusField`.
    @FocusState private var focusedField: LimitFocusField?
    #if os(iOS)
    /// Captured from the `ScrollViewReader` so the focus observer — which lives on
    /// the outer stack, alongside the settle logic it shares a trigger with — can
    /// reach the scroll view. Same capture-on-load pattern the Send form uses.
    @State private var scrollProxy: ScrollViewProxy?
    /// The pending scroll-to-focused-field. Held so a fast hop between fields
    /// cancels the previous one instead of animating to both in turn.
    @State private var keyboardScrollTask: Task<Void, Never>?
    #endif

    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void
    let onPlaceOrder: () -> Void

    var body: some View {
        // Evaluated once and threaded through both consumers — the inline notice
        // and the CTA's disabled state have to agree, and re-deriving it per read
        // would run the affordability math twice on every body pass.
        let balance = vm.balanceState(sourceCoin: fromCoin)
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Asset selection comes first: the user picks what they're
                        // trading before stating the condition it executes under.
                        // The price card still names both assets ("When 1 BTC is
                        // worth X ETH") because that sentence IS the condition —
                        // its chips label the price's units and double as shortcuts
                        // to the same pickers.
                        LimitAssetSwapForm(
                            vm: vm,
                            fromCoin: fromCoin,
                            toCoin: toCoin,
                            sourceAmountText: $sourceAmountText,
                            buyAmountText: $buyAmountText,
                            focusedField: $focusedField,
                            onPickFromAsset: onPickFromAsset,
                            onPickToAsset: onPickToAsset,
                            onSwapAssets: onSwapAssets
                        )

                        LimitPriceCard(
                            vm: vm,
                            priceText: $priceText,
                            usdText: $usdText,
                            focusedField: $focusedField,
                            onPickFromAsset: onPickFromAsset,
                            onPickToAsset: onPickToAsset
                        )

                        LimitExpiryCard(vm: vm)

                        if vm.advancedSwapQueueEnabled == false {
                            LimitUnavailableRow()
                        }

                        if let unroutable = vm.pairUnroutableReason {
                            LimitNoticeRow(message: unroutable.message)
                        }

                        // Says which asset is short — funds or gas — instead of
                        // letting the user find out one screen later at Verify.
                        // Silent while the fee estimate is in flight, so a gas error
                        // is never shown and then withdrawn.
                        if let balanceMessage = balance.noticeMessage {
                            LimitNoticeRow(message: balanceMessage)
                        }

                        if let warning = vm.displayedWarning {
                            LimitWarningRow(warning: warning)
                        }
                    }
                }
                #if os(iOS)
                .onLoad {
                    scrollProxy = proxy
                }
                #endif
            }

            PrimaryButton(
                title: "limitSwap.placeOrder".localized,
                action: {
                    // Settle both amount fields before handing off. Tapping the
                    // CTA does not resign focus on its own, so a Buy amount typed
                    // and never blurred would still be showing the REQUESTED
                    // figure while the order guarantees the derived one.
                    focusedField = nil
                    settleAmountFields()
                    onPlaceOrder()
                }
            )
            .disabled(!vm.canPlaceOrder(sourceCoin: fromCoin))
            .padding(.bottom, 16)
        }
        #if os(iOS)
        // ONE keyboard accessory for the whole form. `.keyboard` toolbars are not
        // scoped to the field they're attached to, so sibling accessories on the
        // (simultaneously rendered) price card and Sell row would merge — the fix
        // is a single toolbar whose content follows `focusedField`. The decimal
        // pad has no return key, so Done is unconditional: every field can be
        // dismissed. The percentage buttons are gated on the Sell amount, the
        // only balance-derived field.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .sellAmount {
                    SwapPercentageButtons(
                        show100: !fromCoin.isNativeToken,
                        showAllPercentageButtons: $showAllPercentageButtons,
                        onTap: handleSellPercentage
                    )
                }
                Spacer()
                Button {
                    // Clearing focus rather than resigning first responder via
                    // UIApplication: this toolbar's own contents switch on
                    // `focusedField`, so dismissing by a route that leaves that
                    // value stale would leave the accessory believing a field is
                    // still being edited.
                    focusedField = nil
                } label: {
                    Text("done".localized)
                }
            }
        }
        #endif
        .onLoad {
            // Reflect an already-populated draft in the editable fields on first
            // appear — otherwise they only sync via onChange and read empty
            // until the user edits them.
            if priceText.isEmpty, vm.draft.targetPrice > 0 {
                priceText = formatLimitPrice(vm.draft.targetPrice)
            }
            if usdText.isEmpty, vm.draft.targetPrice > 0, vm.targetUsdPricePerUnit > 0 {
                let text = formatUsdValue(vm.draft.targetPrice * vm.targetUsdPricePerUnit)
                lastSyncedUsdText = text
                usdText = text
            }
            if sourceAmountText.isEmpty, vm.draft.sourceAmount > 0 {
                sourceAmountText = formatAmount(fromCoin.decimal(for: vm.draft.sourceAmount))
            }
            syncBuyText()
        }
        .onChange(of: sourceAmountText) { _, newText in
            // Absorb the echo of a programmatic settle. Without this, writing the
            // DERIVED deposit back into the Sell field would read as a user edit
            // and hand the driver straight back to Sell — undoing the Buy-driven
            // entry on the very frame it was applied.
            let synced = lastSyncedSellText
            lastSyncedSellText = nil
            guard isUserFieldEdit(newText: newText, lastSyncedText: synced) else { return }
            vm.amountChanged(parseLimitAmount(newText, decimals: vm.draft.fromAsset.decimals))
            // A manual edit clears the selected-percentage highlight (market parity).
            showAllPercentageButtons = true
            syncBuyText()
        }
        .onChange(of: vm.draft.sourceAmount) { _, _ in
            // The deposit is what gets signed. When it moves because the user
            // stated an OUTPUT (or the price shifted under a Buy-driven entry),
            // the Sell field has to follow — otherwise the screen shows one
            // deposit and the memo carries another.
            syncSellText()
        }
        .onChange(of: focusedField) { _, newValue in
            // Both amount fields settle to their derived values on blur. Their
            // guards are focus-based (a value comparison would fight the caret
            // mid-typing, since every keystroke re-derives the other side), so
            // losing focus is what has to trigger the settle.
            syncBuyText()
            syncSellText()
            #if os(iOS)
            scrollFocusedFieldIntoView(newValue)
            #endif
        }
        .onChange(of: buyAmountText) { _, newText in
            // Absorb the one echo of a programmatic settle, so re-deriving the
            // field can't re-enter the setter with its own rounded output.
            let synced = lastSyncedBuyText
            lastSyncedBuyText = nil
            guard isUserFieldEdit(newText: newText, lastSyncedText: synced) else { return }
            vm.buyAmountChanged(parseLimitDecimal(newText))
        }
        .onChange(of: vm.expectedBuyAmount) { _, _ in
            syncBuyText()
        }
        .onChange(of: priceText) { _, newText in
            let parsed = parseLimitPrice(newText)
            if parsed != vm.draft.targetPrice {
                vm.targetPriceChanged(parsed)
            }
        }
        .onChange(of: usdText) { _, newText in
            // Convert USD → canonical asset-terms price only while USD is the
            // ACTIVE (editable) representation. In asset mode `usdText` is synced
            // in the background; gating on the mode stops that from feeding back.
            guard vm.draft.displayUnit == .usd else { return }
            // Absorb the one echo of a programmatic sync so a preset/rate/mode
            // redraw of the USD field can't round the canonical price through the
            // 2-dp USD display (or silently clear the active preset).
            let synced = lastSyncedUsdText
            lastSyncedUsdText = nil
            guard isUserFieldEdit(newText: newText, lastSyncedText: synced) else { return }
            vm.targetPriceChangedFromUsd(parseLimitPrice(newText))
        }
        .onChange(of: vm.draft.targetPrice) { _, newPrice in
            // Sync vm → text only when the local text doesn't already parse to the
            // same Decimal. Preserves a trailing "." while typing and reflects
            // preset-pill taps that mutate vm.
            if parseLimitPrice(priceText) != newPrice {
                priceText = newPrice == 0 ? "" : formatLimitPrice(newPrice)
            }
            syncUsdText(for: newPrice)
        }
        .onChange(of: vm.targetUsdPricePerUnit) { _, _ in
            // The target asset (and thus its USD rate) changed — re-derive the USD
            // field from the unchanged canonical price.
            syncUsdText(for: vm.draft.targetPrice)
        }
        .onChange(of: toCoin) { _, _ in
            // A new target asset makes the old buy figure meaningless (the VM has
            // already handed control back to Sell); re-derive rather than leave a
            // number denominated in an asset that is no longer selected.
            syncBuyText()
        }
        .onChange(of: fromCoin) { _, newCoin in
            // The source coin's decimals changed. `sourceAmountText`'s onChange
            // only fires on TEXT edits, so without this the visible amount ("1")
            // would keep the OLD coin's raw `draft.sourceAmount` (e.g. 1 BTC's
            // 1e8 read as 1e-10 ETH). Reparse the visible text with the new coin's
            // decimals so text ↔ draft stays consistent.
            vm.amountChanged(parseLimitAmount(sourceAmountText, decimals: newCoin.decimals))
        }
    }

    #if os(iOS)
    /// Lift the newly focused field clear of the keyboard.
    ///
    /// The form is taller than the screen once the keyboard is up, and every field
    /// in it is reachable — the Buy row and the price row both sit low enough to
    /// be covered outright, so without this the caret can be under the keyboard the
    /// moment it appears.
    ///
    /// The delay is the load-bearing part. SwiftUI's keyboard avoidance shrinks the
    /// scroll view's visible region as a safe-area inset, and that inset lands a
    /// frame or two AFTER the focus change that caused it. Scrolling immediately
    /// would resolve the anchor against the full-height viewport — i.e. against
    /// where the keyboard is about to be — and leave the field behind it. Waiting
    /// for the inset means the target is placed in what the user can actually see.
    ///
    /// `.center` rather than `.bottom`: the anchored rows are short, so centring
    /// leaves whatever room remains for the controls just below them (the market
    /// reference and preset pills under the price row) instead of pinning the field
    /// flush against the keyboard's top edge.
    ///
    /// Blur (`nil`) deliberately does nothing: the keyboard collapsing already
    /// gives the content its space back, and scrolling on the way out would yank
    /// the page under a user who dismissed the keyboard to look around. With a
    /// hardware keyboard attached there is no inset to wait for, and the scroll
    /// simply brings the focused row into view — still the right outcome.
    private func scrollFocusedFieldIntoView(_ field: LimitFocusField?) {
        keyboardScrollTask?.cancel()
        guard let anchor = LimitScrollAnchor(focus: field) else { return }
        keyboardScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut) {
                scrollProxy?.scrollTo(anchor, anchor: .center)
            }
        }
    }

    /// Sets the Sell amount to `pct`% of the source balance. Assigns the field
    /// text (its `onChange` funnels the value into `draft.sourceAmount`); the
    /// balance math + formatting live in the VM (market parity). Owned by the
    /// parent because the keyboard accessory that calls it is — and iOS-only for
    /// the same reason: macOS has no keyboard accessory, so it has no caller.
    private func handleSellPercentage(_ pct: Int) {
        showAllPercentageButtons = false
        let text = vm.sourceAmountText(forPercentage: pct, of: fromCoin)
        sourceAmountText = text
        // Tell the VM directly rather than relying on the text observer: when the
        // percentage resolves to the text already displayed, no change fires, and
        // the driver would stay `.buy` even though Sell is plainly the side the
        // user just acted on — after which a price change would move the amount
        // they had just pinned.
        vm.amountChanged(parseLimitAmount(text, decimals: vm.draft.fromAsset.decimals))
    }
    #endif

    /// AMOUNT formatting — the Sell and Buy fields, which are quantized to
    /// `limitAmountDisplayPrecision` decimal places so the displayed deposit is
    /// the signed one. The PRICE uses `formatLimitPrice` instead: it is rounded
    /// to significant digits, not decimal places, and 8 decimals would truncate a
    /// small price the moment it was written back to the field.
    private func formatAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    /// USD amount formatted for the editable USD field (no grouping separators
    /// so it round-trips through `parseLimitPrice`).
    private func formatUsdValue(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    /// Settle both amount fields to their canonical values, ignoring focus.
    ///
    /// The per-field syncs decline to write while their field is focused, which
    /// is right during editing but wrong at the moment of commitment: `@FocusState`
    /// is not guaranteed to have cleared by the time the action body runs, so the
    /// guards cannot be relied on to have lifted. This forces the settle.
    private func settleAmountFields() {
        forceSyncSellText()
        forceSyncBuyText()
    }

    /// Re-derive the Sell field from the deposit currently in the draft.
    ///
    /// The draft's `sourceAmount` is what gets signed and broadcast, so the field
    /// showing it must never lag behind: a Buy-driven entry, or a price change
    /// while Buy is driving, both move the deposit without the Sell field being
    /// touched. Declines to write while Sell is focused — that text is the user's
    /// own — and records the value it writes so `onChange(sourceAmountText)` can
    /// tell its own echo from a real edit and not flip the driver back.
    private func syncSellText() {
        guard focusedField != .sellAmount else { return }
        forceSyncSellText()
    }

    private func forceSyncSellText() {
        let amount = vm.draft.sourceAmount
        guard amount > 0 else {
            guard !sourceAmountText.isEmpty else { return }
            lastSyncedSellText = ""
            sourceAmountText = ""
            return
        }
        guard parseLimitAmount(sourceAmountText, decimals: vm.draft.fromAsset.decimals) != amount else {
            return
        }
        let text = formatAmount(fromCoin.decimal(for: amount))
        lastSyncedSellText = text
        sourceAmountText = text
    }

    /// Re-derive the Buy field from the order's guaranteed output.
    ///
    /// Same value-comparison guard the USD mirror uses, and for the same
    /// reason: while Buy is the field being typed into, its text is the user's
    /// stated intent and rewriting it would move the caret. Once the derived
    /// output no longer matches what the text says — because Sell was edited, the
    /// price moved, or the deposit was truncated — the field settles to the
    /// figure the order actually guarantees.
    ///
    /// That settle is why a typed `10` can read back as `9.99999998`: it is the
    /// real minimum, not a rounding artefact, and showing the typed value instead
    /// would overstate what the order promises.
    private func syncBuyText() {
        guard focusedField != .buyAmount else { return }
        forceSyncBuyText()
    }

    private func forceSyncBuyText() {
        let derived = vm.expectedBuyAmount
        guard derived > 0 else {
            guard !buyAmountText.isEmpty else { return }
            lastSyncedBuyText = ""
            buyAmountText = ""
            return
        }
        guard parseLimitDecimal(buyAmountText) != derived else { return }
        // `formatAmount`, NOT `NSDecimalNumber.stringValue`: this field is now
        // EDITABLE and its parser is locale-aware, so writing a locale-neutral
        // "." into a comma-decimal locale would let the value be re-read with the
        // point treated as a grouping separator — the 1000x misparse
        // `parseLimitDecimal` documents. The read-only field this replaced could
        // not be re-parsed, so it never had the hazard.
        let text = formatAmount(derived)
        lastSyncedBuyText = text
        buyAmountText = text
    }

    /// Re-derive `usdText` from the canonical target price, skipping the rewrite
    /// when the current text already maps to `targetPrice` (so active USD typing
    /// isn't clobbered — the mapping is exact because both sides divide the typed
    /// USD by the same rate). Records the written value in `lastSyncedUsdText` so
    /// the resulting `onChange(usdText)` is absorbed instead of feeding back.
    private func syncUsdText(for targetPrice: Decimal) {
        let newText: String
        if vm.targetUsdPricePerUnit > 0 {
            let mappedAsset = parseLimitPrice(usdText) / vm.targetUsdPricePerUnit
            guard mappedAsset != targetPrice else { return }
            let usd = targetPrice * vm.targetUsdPricePerUnit
            newText = usd == 0 ? "" : formatUsdValue(usd)
        } else {
            guard !usdText.isEmpty else { return }
            newText = ""
        }
        lastSyncedUsdText = newText
        usdText = newText
    }
}
