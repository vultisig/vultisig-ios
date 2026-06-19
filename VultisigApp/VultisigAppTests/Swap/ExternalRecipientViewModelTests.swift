//
//  ExternalRecipientViewModelTests.swift
//  VultisigAppTests
//
//  Covers the external-recipient resolve + validate path:
//   1. A name (ENS/THORName) resolves async to the underlying address and the
//      RESOLVED address is what gets persisted (never the raw name).
//   2. A literal valid address persists as-is with no name label.
//   3. An empty field clears the recipient (own-address swap) with no error.
//   4. An unresolvable/invalid entry never persists and surfaces an error, so
//      it can't reach signing.
//   5. The form-layer `AddressValidator` (not ad-hoc code) drives validity.
//

import XCTest
@testable import VultisigApp

@MainActor
final class ExternalRecipientViewModelTests: XCTestCase {

    private let validBtc = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"

    func testNameResolvesToAddressAndPersistsResolved() async {
        // Resolver maps a name to a different (valid) address — the resolved value
        // must persist and the raw name must surface as the label.
        let resolved = validBtc
        let vm = makeVM(initial: "vitalik.eth") { _, _ in resolved }

        var persisted: String? = "sentinel"
        vm.resolveAndPersist { persisted = $0 }
        await settle(vm)

        XCTAssertEqual(persisted, resolved, "The resolved address (not the name) must persist")
        XCTAssertEqual(vm.resolvedNameLabel, "vitalik.eth", "The original name must show as the label")
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isResolving)
    }

    func testLiteralValidAddressPersistsWithoutNameLabel() async {
        let vm = makeVM(initial: validBtc) { input, _ in input }

        var persisted: String?
        vm.resolveAndPersist { persisted = $0 }
        await settle(vm)

        XCTAssertEqual(persisted, validBtc)
        XCTAssertNil(vm.resolvedNameLabel, "A literal address has no name label")
        XCTAssertNil(vm.error)
    }

    func testEmptyFieldClearsRecipientWithoutError() async {
        let vm = makeVM(initial: "") { input, _ in input }

        var persisted: String? = "sentinel"
        vm.resolveAndPersist { persisted = $0 }
        await settle(vm)

        XCTAssertNil(persisted, "An empty field clears the recipient (own-address swap)")
        XCTAssertNil(vm.error, "An empty field is not an error")
    }

    func testUnresolvableEntryDoesNotPersistAndSurfacesError() async {
        struct ResolveError: Error {}
        let vm = makeVM(initial: "not-an-address") { _, _ in throw ResolveError() }

        var persisted: String? = "sentinel"
        vm.resolveAndPersist { persisted = $0 }
        await settle(vm)

        XCTAssertNil(persisted, "An unresolvable entry must never persist — it can't reach signing")
        XCTAssertNotNil(vm.error, "An unresolvable entry must surface an inline error")
        XCTAssertFalse(vm.field.valid)
    }

    func testAddressValidatorRejectsInvalidAddressForChain() {
        // The form-layer validator (not ad-hoc inline code) gates validity.
        let validator = AddressValidator(chain: .bitcoin)
        XCTAssertTrue(validator.validateNonThrowable(value: validBtc))
        XCTAssertFalse(validator.validateNonThrowable(value: "0xnotBitcoin"))
        // Empty is allowed (own-address swap clears the recipient).
        XCTAssertTrue(validator.validateNonThrowable(value: ""))
    }

    // MARK: - Fixtures

    private func makeVM(
        chain: Chain = .bitcoin,
        initial: String?,
        resolver: @escaping (String, Chain) async throws -> String
    ) -> ExternalRecipientViewModel {
        ExternalRecipientViewModel(chain: chain, initialRecipient: initial, resolver: resolver)
    }

    /// Awaits the debounced resolve task so assertions run after it settles.
    private func settle(_ vm: ExternalRecipientViewModel) async {
        for _ in 0..<200 where vm.isResolving {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
