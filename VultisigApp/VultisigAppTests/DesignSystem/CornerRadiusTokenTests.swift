//
//  CornerRadiusTokenTests.swift
//  VultisigAppTests
//
//  Pins the corner-radius scale, and pins the geometry the tokens produce
//  against the numeric literals they replace. A change to either is then a
//  deliberate, visible edit rather than a silent restyle of every surface that
//  reads a token.
//

import SwiftUI
import XCTest
@testable import VultisigApp

final class CornerRadiusTokenTests: XCTestCase {

    /// A rect wide and tall enough that no token on the numeric scale is
    /// clamped by it, so path comparisons below compare the corner shape rather
    /// than SwiftUI's clamping.
    private let rect = CGRect(x: 0, y: 0, width: 320, height: 120)

    // MARK: - The scale

    func testScaleValuesMatchTheDesignScale() {
        XCTAssertEqual(Theme.radius.xs.points, 4)
        XCTAssertEqual(Theme.radius.sm.points, 8)
        XCTAssertEqual(Theme.radius.md.points, 12)
        XCTAssertEqual(Theme.radius.lg.points, 16)
        XCTAssertEqual(Theme.radius.xl.points, 24)
    }

    func testScaleIsStrictlyIncreasing() {
        let scale = allTokens.map(\.points)
        XCTAssertEqual(scale, scale.sorted())
        XCTAssertEqual(Set(scale).count, scale.count)
    }

    // MARK: - Geometry parity with the literals the tokens replace

    /// The tokens have to render exactly what the untokenised call sites render,
    /// or migrating a site is a visual change. Every literal in the app spells
    /// the radius out and leaves the corner style to the SDK's default, so this
    /// compares each token's path against exactly that.
    ///
    /// This is also a tripwire. The default belongs to Apple — it was
    /// `.circular` before the corners-are-continuous SDK and is `.continuous`
    /// now — so if it moves again this test fails, which is the signal that
    /// every *untokenised* surface in the app just restyled itself.
    func testTokenShapesMatchTheImplicitlyStyledLiteralsTheyReplace() {
        let migrated: [(name: String, token: CornerRadius, literal: CGFloat)] = [
            ("xs", Theme.radius.xs, 4),
            ("sm", Theme.radius.sm, 8),
            ("md", Theme.radius.md, 12),
            ("lg", Theme.radius.lg, 16),
            ("xl", Theme.radius.xl, 24)
        ]

        for (name, token, literal) in migrated {
            XCTAssertEqual(
                token.shape.path(in: rect).description,
                RoundedRectangle(cornerRadius: literal).path(in: rect).description,
                "\(name) does not render what RoundedRectangle(cornerRadius: \(literal)) renders"
            )
        }
    }

    // MARK: - pill

    /// SwiftUI clamps a corner radius to half the surface's smaller dimension,
    /// which is what turns a large radius into a capsule. `pill` is therefore
    /// only fully round while it stays above half of the surface it is applied
    /// to — a large-enough surface out-runs it and the corners come back. The
    /// sizes below bracket everything the app can render, up to a full 5K
    /// display, so the token's promise holds by measurement rather than by
    /// "that number looks big".
    func testPillIsFullyRoundAtEverySizeTheAppCanRender() {
        let sizes = [
            CGSize(width: 320, height: 44),     // search field
            CGSize(width: 100, height: 52),     // chip / counter row
            CGSize(width: 1_366, height: 1_024), // iPad landscape
            CGSize(width: 5_120, height: 2_880)  // 5K display
        ]

        for size in sizes {
            let bounds = CGRect(origin: .zero, size: size)
            XCTAssertEqual(
                Theme.radius.pill.shape.path(in: bounds).description,
                Capsule(style: Theme.radius.pill.style).path(in: bounds).description,
                "pill stops clamping to a capsule at \(size)"
            )
        }
    }

    /// The app expresses "fully round" as 50, 60, 99 and 100, and the design
    /// file as 50, 77 and 99. All of them clamp to the same capsule, which is
    /// what lets one semantic token replace all seven numbers without moving a
    /// pixel.
    func testPillRendersTheSameCapsuleAsEveryFullyRoundLiteralInUse() {
        let searchFieldSized = CGRect(x: 0, y: 0, width: 320, height: 44)
        let capsule = Capsule(style: Theme.radius.pill.style).path(in: searchFieldSized).description

        XCTAssertEqual(Theme.radius.pill.shape.path(in: searchFieldSized).description, capsule)

        for literal in [50, 60, 77, 99, 100] as [CGFloat] {
            XCTAssertEqual(
                RoundedRectangle(cornerRadius: literal).path(in: searchFieldSized).description,
                capsule,
                "the fully-round literal \(literal) is not what pill renders at this size"
            )
        }
    }

    func testPillIsNotOnTheNumericScale() {
        let numericScale = allTokens.dropLast().map(\.points)
        XCTAssertFalse(numericScale.contains(Theme.radius.pill.points))
    }

    // MARK: - Corner style

    /// The corner style is the app's single shape switch. If a token ever
    /// carries a different style from its siblings, changing that switch stops
    /// being a one-line edit — which is the whole point of the token layer.
    func testEveryTokenSharesTheSameCornerStyle() {
        XCTAssertEqual(Set(allTokens.map(\.style)).count, 1)
    }

    /// The app's current corner geometry, stated once so a change to it has to
    /// be deliberate and screenshot-reviewed rather than incidental.
    func testCornersAreContinuous() {
        XCTAssertEqual(Theme.radius.xl.style, .continuous)
    }

    // MARK: - Shape

    func testShapeCarriesThePointsAndStyleOfItsToken() {
        let token = Theme.radius.lg
        XCTAssertEqual(token.shape.cornerSize, CGSize(width: token.points, height: token.points))
        XCTAssertEqual(token.shape.style, token.style)
    }

    // MARK: - Helpers

    private var allTokens: [CornerRadius] {
        [
            Theme.radius.xs,
            Theme.radius.sm,
            Theme.radius.md,
            Theme.radius.lg,
            Theme.radius.xl,
            Theme.radius.pill
        ]
    }
}
