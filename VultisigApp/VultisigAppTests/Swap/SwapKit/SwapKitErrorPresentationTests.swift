//
//  SwapKitErrorPresentationTests.swift
//  VultisigAppTests
//
//  Pins the swap tooltip's presentation of `SwapKitError`. Twenty of its
//  twenty-one cases used to render an accurate, domain-correct body under the
//  generic "Unexpected Error" heading, because the enum did not conform to
//  `SwapErrorPresentable` and the view's normalization arm covered exactly one
//  case. These tests hold the whole enum inside the vocabulary, not the cases a
//  given PR happened to touch.
//

import XCTest
@testable import VultisigApp

final class SwapKitErrorPresentationTests: XCTestCase {

    /// A string no localized copy can contain, planted in every associated
    /// value. `testNoCaseLeaksItsUpstreamStringIntoTheBody` then holds for cases
    /// that do not exist yet: a future case carrying a provider string is given
    /// a sample here by the exhaustive switches below, and leaks the sentinel
    /// the moment its body renders that string.
    private static let sentinel = "__upstream_sentinel_7f3a__"

    /// One tag per `SwapKitError` case. Two exhaustive switches close the loop
    /// around it: `tag(of:)` fails to compile when a case is added to
    /// `SwapKitError`, and `sample(for:)` fails to compile when a tag is added
    /// here. A twenty-second case therefore cannot reach `main` without a
    /// presentation decision recorded in `expectedTitleKeys`.
    private enum CaseTag: String, CaseIterable {
        case apiKeyMissing
        case apiKeyInvalid
        case insufficientBalance
        case insufficientAllowance
        case unableToBuildTransaction
        case swapRouteNotFound
        case outputAmountDeviationTooHigh
        case noRoutesFound
        case amountBelowProviderMinimum
        case blackListAsset
        case invalidSourceAddress
        case invalidDestinationAddress
        case isSanctionedAddress
        case addressScreeningFailed
        case unsupportedTxType
        case contradictoryResponse
        case responseEchoMismatch
        case providerNotEnabled
        case routeFiltered
        case malformedAmount
        case generic
    }

    private func sample(for tag: CaseTag) -> SwapKitError {
        switch tag {
        case .apiKeyMissing: return .apiKeyMissing
        case .apiKeyInvalid: return .apiKeyInvalid
        case .insufficientBalance: return .insufficientBalance
        case .insufficientAllowance: return .insufficientAllowance
        case .unableToBuildTransaction: return .unableToBuildTransaction
        case .swapRouteNotFound: return .swapRouteNotFound
        case .outputAmountDeviationTooHigh: return .outputAmountDeviationTooHigh
        case .noRoutesFound: return .noRoutesFound
        case .amountBelowProviderMinimum: return .amountBelowProviderMinimum
        case .blackListAsset: return .blackListAsset
        case .invalidSourceAddress: return .invalidSourceAddress
        case .invalidDestinationAddress: return .invalidDestinationAddress
        case .isSanctionedAddress: return .isSanctionedAddress
        case .addressScreeningFailed: return .addressScreeningFailed
        case .unsupportedTxType: return .unsupportedTxType(Self.sentinel)
        case .contradictoryResponse: return .contradictoryResponse(detail: Self.sentinel)
        case .responseEchoMismatch: return .responseEchoMismatch(detail: Self.sentinel)
        case .providerNotEnabled: return .providerNotEnabled
        case .routeFiltered: return .routeFiltered
        case .malformedAmount: return .malformedAmount(Self.sentinel)
        case .generic: return .generic(message: Self.sentinel)
        }
    }

    private func tag(of error: SwapKitError) -> CaseTag {
        switch error {
        case .apiKeyMissing: return .apiKeyMissing
        case .apiKeyInvalid: return .apiKeyInvalid
        case .insufficientBalance: return .insufficientBalance
        case .insufficientAllowance: return .insufficientAllowance
        case .unableToBuildTransaction: return .unableToBuildTransaction
        case .swapRouteNotFound: return .swapRouteNotFound
        case .outputAmountDeviationTooHigh: return .outputAmountDeviationTooHigh
        case .noRoutesFound: return .noRoutesFound
        case .amountBelowProviderMinimum: return .amountBelowProviderMinimum
        case .blackListAsset: return .blackListAsset
        case .invalidSourceAddress: return .invalidSourceAddress
        case .invalidDestinationAddress: return .invalidDestinationAddress
        case .isSanctionedAddress: return .isSanctionedAddress
        case .addressScreeningFailed: return .addressScreeningFailed
        case .unsupportedTxType: return .unsupportedTxType
        case .contradictoryResponse: return .contradictoryResponse
        case .responseEchoMismatch: return .responseEchoMismatch
        case .providerNotEnabled: return .providerNotEnabled
        case .routeFiltered: return .routeFiltered
        case .malformedAmount: return .malformedAmount
        case .generic: return .generic
        }
    }

    private var allCases: [SwapKitError] { CaseTag.allCases.map(sample) }

    /// The presentation decision for every case, as a key rather than a string,
    /// so a re-worded translation does not fail the test and a silently swapped
    /// key does.
    private let expectedTitleKeys: [CaseTag: String] = [
        .apiKeyMissing: "swapErrorProviderRejectedTitle",
        .apiKeyInvalid: "swapErrorProviderRejectedTitle",
        .providerNotEnabled: "swapErrorProviderRejectedTitle",
        .insufficientBalance: "swapErrorInsufficientFundsTitle",
        .insufficientAllowance: "swapErrorApprovalRequiredTitle",
        .unableToBuildTransaction: "swapErrorRouteUnavailableTitle",
        .noRoutesFound: "swapErrorRouteUnavailableTitle",
        .routeFiltered: "swapErrorRouteUnavailableTitle",
        .unsupportedTxType: "swapErrorRouteUnavailableTitle",
        .contradictoryResponse: "swapErrorRouteUnavailableTitle",
        .responseEchoMismatch: "swapErrorRouteUnavailableTitle",
        .malformedAmount: "swapErrorRouteUnavailableTitle",
        .generic: "swapErrorRouteUnavailableTitle",
        .swapRouteNotFound: "swapErrorRouteExpiredTitle",
        .outputAmountDeviationTooHigh: "swapErrorQuoteExpiredTitle",
        .amountBelowProviderMinimum: "swapErrorAmountTooSmallTitle",
        .blackListAsset: "swapErrorAssetBlockedTitle",
        .invalidSourceAddress: "swapErrorInvalidSourceTitle",
        .invalidDestinationAddress: "swapErrorInvalidDestinationTitle",
        .isSanctionedAddress: "swapErrorAddressScreeningTitle",
        .addressScreeningFailed: "swapErrorAddressScreeningTitle"
    ]

    /// The body key every case must resolve to. Without this, a body assertion
    /// can only compare `SwapErrorPresentation.message(for:)` against
    /// `errorMessage`, which is the same value by construction and passes for a
    /// swapped key.
    private let expectedMessageKeys: [CaseTag: String] = [
        .apiKeyMissing: "swapKitErrorApiKeyMissing",
        .apiKeyInvalid: "swapKitErrorApiKeyInvalid",
        .insufficientBalance: "swapKitErrorInsufficientBalance",
        .insufficientAllowance: "swapKitErrorInsufficientAllowance",
        .unableToBuildTransaction: "swapKitErrorUnableToBuildTransaction",
        .swapRouteNotFound: "swapKitErrorSwapRouteNotFound",
        .outputAmountDeviationTooHigh: "swapKitErrorOutputAmountDeviationTooHigh",
        .noRoutesFound: "swapKitErrorNoRoutesFound",
        .amountBelowProviderMinimum: "swapErrorAmountTooSmallDescription",
        .blackListAsset: "swapKitErrorBlackListAsset",
        .invalidSourceAddress: "swapKitErrorInvalidSourceAddress",
        .invalidDestinationAddress: "swapKitErrorInvalidDestinationAddress",
        .isSanctionedAddress: "swapKitErrorAddressScreening",
        .addressScreeningFailed: "swapKitErrorAddressScreening",
        // The five that carry an upstream string share the route-unusable copy.
        .unsupportedTxType: "swapKitErrorUnableToBuildTransaction",
        .contradictoryResponse: "swapKitErrorUnableToBuildTransaction",
        .responseEchoMismatch: "swapKitErrorUnableToBuildTransaction",
        .malformedAmount: "swapKitErrorUnableToBuildTransaction",
        .generic: "swapKitErrorUnableToBuildTransaction",
        .providerNotEnabled: "swapKitErrorProviderNotEnabled",
        .routeFiltered: "swapKitErrorRouteFiltered"
    ]

    /// Every locale the app is expected to ship. Pinned rather than derived so a
    /// build that dropped a `.lproj` fails here instead of quietly shrinking the
    /// per-locale loops below to nothing.
    private static let expectedLocales = ["de", "en", "es", "hr", "it", "ko", "pt", "zh-Hans"]

    /// The title keys this change introduces. They are the ones that can be
    /// missing from a locale, so they get the per-locale check.
    private let newTitleKeys = [
        "swapErrorAddressScreeningTitle",
        "swapErrorApprovalRequiredTitle",
        "swapErrorAssetBlockedTitle",
        "swapErrorInvalidSourceTitle",
        "swapErrorQuoteExpiredTitle",
        "swapErrorRouteExpiredTitle"
    ]

    /// Every localization actually included in the app bundle, so a new shipping
    /// locale is covered without another manifest.
    private static var shippedLocales: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted()
    }

    /// Localized value for `key` in `bundle`, or `nil` when the key is missing.
    /// `"key".localized` echoes the key back on a miss, so asserting against it
    /// proves nothing about the strings file; this does.
    private func localizedValue(forKey key: String, in bundle: Bundle = .main) -> String? {
        let sentinel = "__missing_localization__"
        let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
        return value == sentinel ? nil : value
    }

    private struct SourceParseFailure: Error, CustomStringConvertible {
        let description: String
    }

    /// Every case name declared by `SwapKitError`, read from its own source.
    /// Swift cannot make an enum with associated values `CaseIterable`, so the
    /// two switches above force an author to *visit* this file when a case is
    /// added — but not to give it its own tag. Comparing against the declaration
    /// closes that: a case mapped onto an existing tag has no sample, and shows
    /// up here as a name with no tag. Anchored at `#filePath` the same way
    /// `SigningGoldenStore` and the Figma parity harness anchor theirs.
    ///
    /// Reads the case list as a region rather than matching a line shape, and
    /// throws on anything it does not recognise. A parser that skipped what it
    /// could not read would answer with a short list that still matched the tags,
    /// which is the one failure this whole check exists to prevent.
    private func declaredCaseNames() throws -> Set<String> {
        let source = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VultisigApp/Blockchain/Swaps/SwapKit/SwapKitError.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        var names: Set<String> = []
        var insideDeclaration = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard insideDeclaration else {
                insideDeclaration = line.hasPrefix("enum SwapKitError")
                continue
            }
            if line.isEmpty || line.hasPrefix("//") { continue }
            // The case list ends at the enum's first other member.
            if line == "}" || ["init", "var", "func", "static", "let"].contains(where: line.hasPrefix) {
                break
            }
            guard line.hasPrefix("case ") else {
                throw SourceParseFailure(description: "unrecognised line in the case list: \(rawLine)")
            }
            for piece in Self.splitOnTopLevelCommas(line.dropFirst("case ".count)) {
                let name = piece
                    .trimmingCharacters(in: .whitespaces)
                    .prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                guard !name.isEmpty else {
                    throw SourceParseFailure(description: "unparsable case declaration: \(rawLine)")
                }
                names.insert(String(name))
            }
        }
        guard !names.isEmpty else {
            throw SourceParseFailure(description: "no cases found — the enum declaration was not located")
        }
        return names
    }

    /// Commas inside an associated-value list do not separate cases.
    private static func splitOnTopLevelCommas(_ text: Substring) -> [Substring] {
        var pieces: [Substring] = []
        var depth = 0
        var start = text.startIndex
        for index in text.indices {
            switch text[index] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
            case "," where depth == 0:
                pieces.append(text[start..<index])
                start = text.index(after: index)
            default:
                break
            }
        }
        pieces.append(text[start...])
        return pieces
    }

    /// The bundle for a single `.lproj`, which resolves keys from that locale
    /// alone with no fallback. `Bundle.main` answers for the *active*
    /// localization only, so a key present in `en` and missing from `ko` reads as
    /// covered when the whole point of the check is that it isn't.
    private func bundle(forLocale locale: String) -> Bundle? {
        Bundle.main.path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    // MARK: - The reported bug, through the path the view actually uses

    func testNoCaseFallsBackToUnexpectedErrorTitle() {
        let generic = SwapCryptoLogic.Errors.unexpectedError.errorTitle
        for error in allCases {
            XCTAssertNotEqual(
                SwapErrorPresentation.title(for: error),
                generic,
                "\(tag(of: error).rawValue) is still titled generically"
            )
        }
    }

    func testEveryCaseIsInsideTheTooltipVocabulary() {
        for error in allCases {
            XCTAssertNotNil(
                SwapErrorPresentation.presentable(for: error),
                "\(tag(of: error).rawValue) is outside the tooltip vocabulary"
            )
        }
    }

    func testEveryDeclaredCaseHasItsOwnTag() throws {
        // Guards the hole the two switches cannot: an author who satisfies
        // `tag(of:)` by pointing a new case at an existing tag leaves it with no
        // sample, and every other test here passes without ever seeing it.
        XCTAssertEqual(
            try declaredCaseNames(),
            Set(CaseTag.allCases.map(\.rawValue)),
            "SwapKitError's declared cases and this file's tags have diverged"
        )
    }

    func testEveryCaseHasNonEmptyTitleAndMessage() {
        for error in allCases {
            let name = tag(of: error).rawValue
            XCTAssertFalse(error.errorTitle.isEmpty, "\(name) has an empty title")
            XCTAssertFalse(error.errorMessage.isEmpty, "\(name) has an empty message")
        }
    }

    func testTitleKeyPerCase() {
        for error in allCases {
            let name = tag(of: error).rawValue
            guard let key = expectedTitleKeys[tag(of: error)] else {
                XCTFail("no expected title key for \(name)")
                continue
            }
            guard let value = localizedValue(forKey: key) else {
                XCTFail("\(key) is missing from Localizable.strings (\(name))")
                continue
            }
            XCTAssertEqual(SwapErrorPresentation.title(for: error), value, "wrong title key for \(name)")
        }
    }

    func testBodyKeyPerCase() {
        // Asserted against the localized value of an expected key, not against
        // `errorMessage`: the tooltip reads the body straight off the conformance,
        // so comparing the two would hold for any key at all.
        for error in allCases {
            let name = tag(of: error).rawValue
            guard let key = expectedMessageKeys[tag(of: error)] else {
                XCTFail("no expected body key for \(name)")
                continue
            }
            guard let value = localizedValue(forKey: key) else {
                XCTFail("\(key) is missing from Localizable.strings (\(name))")
                continue
            }
            XCTAssertEqual(SwapErrorPresentation.message(for: error), value, "wrong body key for \(name)")
        }
    }

    // MARK: - Raw upstream text never reaches the tooltip body

    func testNoCaseLeaksItsUpstreamStringIntoTheBody() {
        for error in allCases {
            XCTAssertFalse(
                error.errorMessage.contains(Self.sentinel),
                "\(tag(of: error).rawValue) renders its upstream string in the tooltip body"
            )
        }
    }

    func testTxTypeAmountAndProviderStringsSurviveInTheDiagnosticDescription() {
        // `errorDescription` is the diagnostic channel (`localizedDescription`,
        // logger lines). Replacing the body must not cost the support log the one
        // detail that says what upstream actually sent.
        for error in [
            SwapKitError.unsupportedTxType(Self.sentinel),
            .malformedAmount(Self.sentinel),
            .generic(message: Self.sentinel)
        ] {
            XCTAssertEqual(error.errorDescription?.contains(Self.sentinel), true, "\(tag(of: error).rawValue)")
        }
    }

    func testResponseRefusalDetailsSurviveInRefusalDetail() {
        // These two never put their detail in `errorDescription` either — it has
        // always been carried by `refusalDetail` for the rejection log.
        for error in [
            SwapKitError.contradictoryResponse(detail: Self.sentinel),
            .responseEchoMismatch(detail: Self.sentinel)
        ] {
            XCTAssertEqual(error.refusalDetail, Self.sentinel, "\(tag(of: error).rawValue)")
        }
    }

    func testGenericStopsRenderingTheProviderStringAsTheBody() {
        // The visible behaviour change. `generic` is raised both from an
        // unclassified upstream code and from app-side encode failures, and used
        // to put either verbatim in front of the user.
        let raw = "SwapKit PSBT payload is not valid base64"
        let error = SwapKitError.generic(message: raw)
        XCTAssertEqual(error.errorDescription, raw)
        XCTAssertNotEqual(SwapErrorPresentation.message(for: error), raw)
        XCTAssertEqual(
            SwapErrorPresentation.message(for: error),
            "swapKitErrorUnableToBuildTransaction".localized
        )
    }

    // MARK: - The one case that already had a presentation keeps it

    func testAmountBelowProviderMinimumStillPresentsAsSwapAmountTooSmall() {
        // It used to reach the tooltip by being normalized into
        // `SwapCryptoLogic.Errors.swapAmountTooSmall`. That arm is gone; the
        // rendered pair must be unchanged.
        let error = SwapKitError.amountBelowProviderMinimum
        let equivalent = SwapCryptoLogic.Errors.swapAmountTooSmall
        XCTAssertEqual(SwapErrorPresentation.title(for: error), equivalent.errorTitle)
        XCTAssertEqual(SwapErrorPresentation.message(for: error), equivalent.errorMessage)
    }

    func testNonSwapErrorsStillFallBackToTheirLocalizedDescription() {
        // Removing the normalization arm must not narrow the fallback that
        // fee-path and transport failures depend on.
        let error = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "an unclassifiable failure"]
        )
        XCTAssertNil(SwapErrorPresentation.presentable(for: error))
        XCTAssertEqual(
            SwapErrorPresentation.title(for: error),
            SwapCryptoLogic.Errors.unexpectedError.errorTitle
        )
        XCTAssertEqual(SwapErrorPresentation.message(for: error), "an unclassifiable failure")
    }

    // MARK: - Localization

    func testTheExpectedEightLocalesActuallyShip() {
        // Without this, every per-locale loop below iterates over whatever the
        // bundle happens to contain — one locale, or none — and passes.
        XCTAssertEqual(Self.shippedLocales, Self.expectedLocales)
    }

    func testNewTitleKeysExistInEveryShippedLocale() {
        // Guards the "missing key leaks a raw camelCase identifier to the user"
        // failure mode that `"key".localized == "key".localized` cannot see — and
        // per locale, because the active-localization lookup would pass on `en`
        // alone while a Korean user saw the key.
        for locale in Self.shippedLocales {
            guard let bundle = bundle(forLocale: locale) else {
                XCTFail("\(locale).lproj does not ship in the app bundle")
                continue
            }
            for key in newTitleKeys {
                XCTAssertNotNil(
                    localizedValue(forKey: key, in: bundle),
                    "\(key) is missing from \(locale).lproj/Localizable.strings"
                )
            }
        }
    }

    func testEveryTitleKeyInUseExistsInEveryShippedLocale() {
        for locale in Self.shippedLocales {
            guard let bundle = bundle(forLocale: locale) else {
                XCTFail("\(locale).lproj does not ship in the app bundle")
                continue
            }
            for key in Set(expectedTitleKeys.values).sorted() {
                XCTAssertNotNil(
                    localizedValue(forKey: key, in: bundle),
                    "\(key) is missing from \(locale).lproj/Localizable.strings"
                )
            }
        }
    }

    func testPerLocaleLookupDoesNotFallBackToEnglish() {
        // Gives the two per-locale assertions their teeth. If `Bundle(path:)`
        // resolved through the English table, a key missing from a locale would
        // still answer and both checks would pass vacuously.
        guard let english = bundle(forLocale: "en"),
              let englishValue = localizedValue(forKey: "swapErrorRouteExpiredTitle", in: english) else {
            XCTFail("en.lproj does not ship in the app bundle")
            return
        }
        for locale in Self.shippedLocales where locale != "en" {
            guard let bundle = bundle(forLocale: locale) else {
                XCTFail("\(locale).lproj does not ship in the app bundle")
                continue
            }
            XCTAssertNotEqual(
                localizedValue(forKey: "swapErrorRouteExpiredTitle", in: bundle),
                englishValue,
                "\(locale) answered with the English value — the per-locale lookup is falling back"
            )
        }
    }
}
