//
//  SignBitcoinDisplayView.swift
//  VultisigApp
//
//  Renders the structured PSBT (`SignBitcoin`) keysign payload so co-signers
//  can verify every input/output and the computed fee before approving.
//  Mirrors the Windows/extension PSBT confirmation panel; the structured
//  proto exists precisely so devices don't have to trust an opaque blob.
//

import SwiftUI

struct SignBitcoinDisplayView: View {
    let signBitcoin: SignBitcoin

    @State private var isExpanded: Bool = true

    private var totalIn: Int64 { signBitcoin.inputs.reduce(0) { $0 + $1.amount } }
    private var totalOut: Int64 { signBitcoin.outputs.reduce(0) { $0 + $1.amount } }
    // Show the raw delta — clamping to zero would mask malformed PSBTs from
    // a co-signer. Negative values are surfaced visually below.
    private var fee: Int64 { totalIn - totalOut }
    private var hasInvalidFee: Bool { fee < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("psbtTransactionDetails".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    inputsSection
                    outputsSection
                    feeRow
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }

    // MARK: - Sections

    private var inputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("psbtInputs", count: signBitcoin.inputs.count)
            ForEach(Array(signBitcoin.inputs.enumerated()), id: \.offset) { index, input in
                inputRow(index: index, input: input)
            }
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("psbtOutputs", count: signBitcoin.outputs.count)
            ForEach(Array(signBitcoin.outputs.enumerated()), id: \.offset) { index, output in
                outputRow(index: index, output: output)
            }
        }
    }

    private var feeRow: some View {
        HStack(spacing: 4) {
            Text("psbtNetworkFee".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(minWidth: 52, alignment: .leading)
            Spacer()
            Text(formatBtc(satoshis: fee))
                .foregroundStyle(hasInvalidFee ? Theme.colors.alertWarning : Theme.colors.textPrimary)
                .font(Theme.fonts.priceBodyS)
        }
        .font(Theme.fonts.bodySMedium)
    }

    // MARK: - Rows

    private func sectionHeader(_ key: String, count: Int) -> some View {
        Text("\(key.localized) (\(count))")
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inputRow(index: Int, input: BitcoinInput) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(index)")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(formatOutpoint(hash: input.hash, index: input.index))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(formatBtc(satoshis: input.amount))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            HStack(spacing: 8) {
                Text(input.scriptType.uppercased())
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
                if input.isOurs {
                    Text("psbtSignedByThisDevice".localized)
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.alertSuccess)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.colors.bgPrimary))
    }

    private func outputRow(index: Int, output: BitcoinOutput) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(index)")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(displayLabel(for: output))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(formatBtc(satoshis: output.amount))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            if let badge = badgeText(for: output) {
                HStack {
                    Text(badge)
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.colors.bgPrimary))
    }

    // MARK: - Formatting

    private func displayLabel(for output: BitcoinOutput) -> String {
        if output.opReturnData != nil {
            return "psbtOpReturn".localized
        }
        if !output.address.isEmpty {
            return output.address
        }
        return output.scriptPubKey
    }

    private func badgeText(for output: BitcoinOutput) -> String? {
        if let data = output.opReturnData {
            return String(format: "psbtOpReturnFormat".localized, data)
        }
        if output.isChange {
            return "psbtChangeMarker".localized
        }
        return nil
    }

    private func formatOutpoint(hash: String, index: UInt32) -> String {
        // Bitcoin txids are conventionally truncated to first 8 / last 8 chars
        // when displayed in compact UIs; we render the full txid:vout but rely
        // on lineLimit + truncationMode for clipping.
        return "\(hash):\(index)"
    }

    /// Format satoshis as a BTC-denominated string with up to 8 decimals.
    private func formatBtc(satoshis: Int64) -> String {
        let value = Decimal(satoshis) / Decimal(100_000_000)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "\(satoshis)"
        return "\(formatted) BTC"
    }
}
