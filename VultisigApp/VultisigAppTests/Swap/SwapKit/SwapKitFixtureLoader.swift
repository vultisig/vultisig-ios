//
//  SwapKitFixtureLoader.swift
//  VultisigAppTests
//
//  Bundle helper for the SwapKit decoder + filter tests. Resources land in
//  the test target's `Bundle(for:)` root because the `__fixtures__` directory
//  is registered as a `resources` buildPhase in `project.yml`.
//

import Foundation

enum SwapKitFixtureLoader {
    /// Fixtures are bundled as a folder reference under `__fixtures__/` (see
    /// the `VultisigAppTests` target in `project.yml`). Resolving via
    /// `subdirectory:` keeps them out of the bundle root, which avoids
    /// colliding with `ChainHelperTests.testChainHelpers` (it enumerates
    /// every top-level JSON in the resource path).
    private static let fixturesSubdirectory = "__fixtures__"

    static func loadData(_ name: String) throws -> Data {
        let bundle = Bundle(for: SwapKitFixtureLoaderAnchor.self)
        // No bundle-root fallback: requiring `__fixtures__/` keeps misplaced
        // fixtures from silently resolving to an unrelated same-named JSON
        // in another test area, and it surfaces project.yml regressions
        // (the resources buildPhase deleting the folder reference) here
        // rather than masking them with a confusing decode error.
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: fixturesSubdirectory
        ) else {
            throw NSError(
                domain: "SwapKitFixtureLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing fixture: \(fixturesSubdirectory)/\(name).json"]
            )
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let data = try loadData(name)
        return try JSONDecoder().decode(type, from: data)
    }
}

// Anchor class so `Bundle(for:)` resolves to the test bundle.
private final class SwapKitFixtureLoaderAnchor {}
