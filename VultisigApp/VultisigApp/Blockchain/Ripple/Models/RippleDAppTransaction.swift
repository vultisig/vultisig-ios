//
//  RippleDAppTransaction.swift
//  VultisigApp
//

import BigInt
import Foundation

/// A best-effort, display-only decode of a dApp-supplied XRPL transaction JSON
/// (`signRipple.rawJson`), so the co-signer reviews readable terms — type,
/// destination, amounts, issuer — instead of an opaque blob. Port of the
/// Windows `parseRippleTx`.
///
/// This is NOT a security boundary: the signing fail-closed checks live in
/// `RippleHelper.dappSigningInput`. This parser only decides what to render.
/// It NEVER throws — `parse` returns `nil` when the JSON can't be decoded into
/// a recognizable transaction, and the display falls back to the raw JSON with
/// a caution notice (a signing screen must never go blank). It also fails
/// closed on a *present-but-undecodable value field*: an `Amount` / `SendMax` /
/// etc. that exists but can't be decoded returns `nil` rather than a
/// seemingly-complete screen that silently hides value.
struct RippleDAppTransaction: Equatable {

    /// A decoded XRPL amount: native XRP (drops → XRP) or an issued currency.
    enum Amount: Equatable {
        /// Trimmed XRP magnitude (drops / 10^6), without the "XRP" unit.
        case native(xrp: String)
        /// An issued currency: the on-ledger value string, the (decoded)
        /// currency code, and the issuer address.
        case issued(value: String, currency: String, issuer: String)
    }

    /// A rendered value carried by a labelled row.
    enum Value: Equatable {
        case text(String)
        case amount(Amount)
    }

    struct Field: Equatable {
        let labelKey: String
        let value: Value
    }

    let transactionType: String
    let fields: [Field]

    // MARK: - Parsing

    /// Value-bearing amount fields, in the exact render order, paired with their
    /// display label key.
    private static let amountFields: [(key: String, labelKey: String)] = [
        ("Amount", "rippleFieldAmount"),
        ("SendMax", "rippleFieldSendMax"),
        ("DeliverMin", "rippleFieldDeliverMin"),
        ("TakerGets", "rippleFieldTakerGets"),
        ("TakerPays", "rippleFieldTakerPays"),
        ("LimitAmount", "rippleFieldTrustLimit")
    ]

    private static let dropsPerXrp = BigInt(1_000_000)

    static func parse(rawJson: String) -> RippleDAppTransaction? {
        guard let data = rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let tx = object as? [String: Any],
              let transactionType = tx["TransactionType"] as? String else {
            return nil
        }

        var fields: [Field] = []

        // 1. Destination (string).
        if let destination = tx["Destination"] as? String {
            fields.append(Field(labelKey: "rippleFieldDestination", value: .text(destination)))
        }

        // 2. Value-bearing amount fields, in order. A present-but-undecodable
        //    value field fails closed (return nil) — never hide value behind a
        //    seemingly-complete screen.
        for field in amountFields where tx[field.key] != nil {
            guard let amount = parseAmount(tx[field.key]) else {
                return nil
            }
            fields.append(Field(labelKey: field.labelKey, value: .amount(amount)))
        }

        // 3. DestinationTag (number).
        if let destinationTag = integerValue(tx["DestinationTag"]) {
            fields.append(Field(labelKey: "rippleFieldDestinationTag", value: .text(destinationTag)))
        }

        // 4. OfferSequence (number).
        if let offerSequence = integerValue(tx["OfferSequence"]) {
            fields.append(Field(labelKey: "rippleFieldOfferSequence", value: .text(offerSequence)))
        }

        return RippleDAppTransaction(transactionType: transactionType, fields: fields)
    }

    // MARK: - Helpers

    /// Decodes an XRPL amount. Returns `nil` when the value is present but not
    /// decodable (a numeric-looking drops string that isn't numeric, or an
    /// issued-currency object missing currency/issuer/value).
    private static func parseAmount(_ value: Any?) -> Amount? {
        if let drops = value as? String {
            guard let dropsInt = BigInt(drops) else { return nil }
            return .native(xrp: formatDrops(dropsInt))
        }
        if let iou = value as? [String: Any] {
            guard let iouValue = iou["value"] as? String,
                  let currency = iou["currency"] as? String,
                  let issuer = iou["issuer"] as? String else {
                return nil
            }
            return .issued(value: iouValue, currency: decodeCurrency(currency), issuer: issuer)
        }
        return nil
    }

    /// Renders XRP drops (base 10^6) as a trimmed decimal string.
    private static func formatDrops(_ drops: BigInt) -> String {
        let negative = drops < 0
        let magnitude = negative ? -drops : drops
        let whole = magnitude / dropsPerXrp
        let fraction = magnitude % dropsPerXrp

        var result = String(whole)
        if fraction != 0 {
            var fractionStr = String(fraction)
            if fractionStr.count < 6 {
                fractionStr = String(repeating: "0", count: 6 - fractionStr.count) + fractionStr
            }
            while fractionStr.hasSuffix("0") { fractionStr.removeLast() }
            result += ".\(fractionStr)"
        }
        return negative && result != "0" ? "-\(result)" : result
    }

    /// A 40-hex currency code decoded to its ASCII ticker when the decoded
    /// bytes are printable; otherwise the code is passed through unchanged.
    /// Standard 3-character codes pass through directly.
    private static func decodeCurrency(_ currency: String) -> String {
        guard currency.utf16.count == 40, currency.allSatisfy(isAsciiHexDigit) else {
            return currency
        }
        var bytes: [UInt8] = []
        var index = currency.startIndex
        while index < currency.endIndex {
            let next = currency.index(index, offsetBy: 2)
            guard let byte = UInt8(currency[index..<next], radix: 16) else { return currency }
            bytes.append(byte)
            index = next
        }
        // Strip trailing NUL padding.
        while bytes.last == 0 { bytes.removeLast() }
        guard !bytes.isEmpty, bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }) else {
            return currency
        }
        return String(bytes: bytes, encoding: .utf8) ?? currency
    }

    /// ASCII `[0-9A-Fa-f]` — mirrors the SDK's `/^[0-9a-fA-F]{40}$/` (Swift's
    /// Unicode-wide `isHexDigit` would accept full-width / non-ASCII digits).
    private static func isAsciiHexDigit(_ char: Character) -> Bool {
        guard let ascii = char.asciiValue else { return false }
        return (ascii >= 0x30 && ascii <= 0x39)
            || (ascii >= 0x41 && ascii <= 0x46)
            || (ascii >= 0x61 && ascii <= 0x66)
    }

    /// Extracts an XRPL integer field (DestinationTag / OfferSequence) rendered
    /// as its decimal string. XRPL emits these as JSON numbers; a value that is
    /// present but not an integer number is ignored (the row is simply omitted).
    private static func integerValue(_ value: Any?) -> String? {
        guard let number = value as? NSNumber else { return nil }
        // Reject booleans and non-integral doubles bridged as NSNumber.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue == doubleValue.rounded(), doubleValue >= 0 else { return nil }
        return number.stringValue
    }
}
