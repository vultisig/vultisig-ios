//
//  SignSuiDisplayView.swift
//  VultisigApp
//
//  Renders the decoded Sui Programmable Transaction Block (PTB) carried by a
//  `signSui` keysign payload on the verify / join screens, so co-signers see
//  the actual transaction — every command and every input — instead of an
//  empty "0 SUI" send card. Mirrors the Windows `SignSuiDisplay`.
//

import SwiftUI

struct SignSuiDisplayView: View {
    let signSui: SignSui

    @State private var areCommandsExpanded: Bool = false
    @State private var areInputsExpanded: Bool = false
    @State private var areRawBytesExpanded: Bool = false

    private var summary: SuiTransactionDataSummary? {
        SuiTransactionDataParser.parse(base64TransactionData: signSui.unsignedTxMsg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary {
                summaryCard(summary)
                commandsSection(summary)
                inputsSection(summary)
            }
            rawBytesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary

    private func summaryCard(_ summary: SuiTransactionDataSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("suiTransactionSummary".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            summaryRow("from".localized, value: summary.sender, mono: true)
            summaryRow("gasBudget".localized, value: Self.formatSuiAmount(summary.gasBudget))
            summaryRow("gasPrice".localized, value: "\(summary.gasPrice) MIST")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
    }

    // MARK: - Commands

    @ViewBuilder
    private func commandsSection(_ summary: SuiTransactionDataSummary) -> some View {
        if !summary.commands.isEmpty {
            collapsibleSection(
                title: "\("commands".localized) (\(summary.commandCount))",
                isExpanded: $areCommandsExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(summary.commands.enumerated()), id: \.offset) { index, command in
                        commandRow(command, index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commandRow(_ command: SuiCommand, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch command {
            case let .moveCall(package, module, function, typeArguments, arguments):
                commandTitle("\(index). \("moveCall".localized)")
                detailMono("\(package)::\(module)::\(function)")
                if !typeArguments.isEmpty {
                    detail("\("typeArguments".localized): \(typeArguments.map(Self.shortenMoveType).joined(separator: ", "))")
                }
                if !arguments.isEmpty {
                    detail("\("arguments".localized): \(arguments.map(Self.renderArgument).joined(separator: ", "))")
                }
            case let .transferObjects(objects, address):
                commandTitle("\(index). \("transferObjects".localized)")
                detail("\("suiObjectsTo".localized): \(Self.renderArgument(address))")
                detail(objects.map(Self.renderArgument).joined(separator: ", "))
            case let .splitCoins(coin, amounts):
                commandTitle("\(index). \("splitCoins".localized)")
                detail("\("suiSplitFrom".localized): \(Self.renderArgument(coin))")
                detail("\("arguments".localized): \(amounts.map(Self.renderArgument).joined(separator: ", "))")
            case let .mergeCoins(destination, sources):
                commandTitle("\(index). \("mergeCoins".localized)")
                detail("\("suiMergeInto".localized): \(Self.renderArgument(destination))")
                detail(sources.map(Self.renderArgument).joined(separator: ", "))
            case let .publish(moduleCount, dependencyCount):
                commandTitle("\(index). \("publish".localized)")
                detail("\("modules".localized): \(moduleCount), \("dependencies".localized): \(dependencyCount)")
            case let .makeMoveVec(type, elements):
                commandTitle("\(index). \("makeMoveVec".localized)")
                if let type {
                    detailMono(Self.shortenMoveType(type))
                }
                detail("\("elements".localized): \(elements.count)")
            case let .upgrade(moduleCount, dependencyCount, package, _):
                commandTitle("\(index). \("upgrade".localized)")
                detailMono(package)
                detail("\("modules".localized): \(moduleCount), \("dependencies".localized): \(dependencyCount)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inputs

    @ViewBuilder
    private func inputsSection(_ summary: SuiTransactionDataSummary) -> some View {
        if !summary.inputs.isEmpty {
            collapsibleSection(
                title: "\("inputs".localized) (\(summary.inputCount))",
                isExpanded: $areInputsExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(summary.inputs.enumerated()), id: \.offset) { index, input in
                        inputRow(input, index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inputRow(_ input: SuiPtbInput, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch input {
            case let .pure(bytes):
                let decoded = Self.decodePure(bytes)
                commandTitle("[\(index)] \("inputPure".localized) · \(decoded.label)")
                detailMono(decoded.display)
            case let .object(kind, objectId, mutable):
                let mutabilitySuffix = mutable.map {
                    " (\($0 ? "suiMutable".localized : "suiReadOnly".localized))"
                } ?? ""
                commandTitle("[\(index)] \(kind.rawValue)\(mutabilitySuffix)")
                detailMono(objectId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Raw bytes

    private var rawBytesSection: some View {
        collapsibleSection(title: "transactionBytes".localized, isExpanded: $areRawBytesExpanded) {
            Text(signSui.unsignedTxMsg)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.colors.turquoise)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.colors.bgPrimary)
                .cornerRadius(8)
        }
    }

    // MARK: - Building blocks

    private func collapsibleSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text(title)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Spacer()
                    Icon(.chevronDown, color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                }
                .padding(16)
            }
            .buttonStyle(.borderless)

            if isExpanded.wrappedValue {
                content()
                    .padding([.horizontal, .bottom], 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private func commandTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailMono(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.colors.textTertiary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(_ title: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Rendering helpers

private extension SignSuiDisplayView {

    /// Renders a PTB argument reference, mirroring the Windows `renderArgument`.
    static func renderArgument(_ argument: SuiArgument) -> String {
        switch argument {
        case .gasCoin:
            return "GasCoin"
        case let .input(index):
            return "\("input".localized) \(index)"
        case let .result(index):
            return "↳ \("suiResultOfCmd".localized) \(index)"
        case let .nestedResult(commandIndex, resultIndex):
            return "↳ \("suiResultOfCmd".localized) \(commandIndex)[\(resultIndex)]"
        }
    }

    /// Format a MIST gas budget as a trimmed SUI string (1 SUI = 10^9 MIST),
    /// mirroring the Windows `formatSuiAmount`. e.g. `34265772` → `0.034265772 SUI`.
    static func formatSuiAmount(_ mist: UInt64) -> String {
        let mistPerSui: UInt64 = 1_000_000_000
        let whole = mist / mistPerSui
        let fractional = mist % mistPerSui
        guard fractional != 0 else { return "\(whole) SUI" }
        var fractionalStr = String(format: "%09llu", fractional)
        while fractionalStr.hasSuffix("0") { fractionalStr.removeLast() }
        return "\(whole).\(fractionalStr) SUI"
    }

    /// Compress `0xabc…::module::Name` to `module::Name`; generics recurse so
    /// `Coin<0xabc…::navx::NAVX>` becomes `Coin<navx::NAVX>`.
    static func shortenMoveType(_ typeTag: String) -> String {
        let pattern = "0x[0-9a-fA-F]+::([^,<>\\s]+)::([^,<>\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return typeTag }
        let range = NSRange(typeTag.startIndex..., in: typeTag)
        return regex.stringByReplacingMatches(in: typeTag, range: range, withTemplate: "$1::$2")
    }

    struct DecodedPure {
        let label: String
        let display: String
    }

    /// Best-effort decode of a `Pure` input's BCS bytes into a recognizable
    /// primitive by byte length, mirroring the Windows `decodePureValue` (the
    /// offline, no-ABI-hint path). Falls back to raw hex for unknown widths.
    static func decodePure(_ bytes: Data) -> DecodedPure {
        let raw = "0x" + bytes.map { String(format: "%02x", $0) }.joined()
        switch bytes.count {
        case 1:
            let byte = bytes[bytes.startIndex]
            if byte == 0 || byte == 1 {
                return DecodedPure(label: "bool", display: byte == 1 ? "true" : "false")
            }
            return DecodedPure(label: "u8", display: String(byte))
        case 8:
            return DecodedPure(label: "u64", display: String(readLEUInt64(bytes)))
        case 16:
            return DecodedPure(label: "u128", display: raw)
        case 32:
            return DecodedPure(label: "address", display: raw)
        default:
            return DecodedPure(label: "\("bytes".localized) (\(bytes.count))", display: raw)
        }
    }

    static func readLEUInt64(_ bytes: Data) -> UInt64 {
        var value: UInt64 = 0
        for (i, byte) in bytes.prefix(8).enumerated() {
            value |= UInt64(byte) << (8 * i)
        }
        return value
    }
}
