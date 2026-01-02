//
//  CircularProgressIndicator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/08/2025.
//

import SwiftUI

struct CircularProgressIndicator: View {
    var size: CGFloat = 24
    var lineWidth: CGFloat = 2
    var tint: Color = Theme.colors.textSecondary
    var speed: Double = 1.0 // <1 slower, >1 faster

    // Material-ish constants
    private let rotationDuration: Double = 1.332  // seconds per rotation
    private let startAngleOffset: Double = -90    // 12 o'clock
    private let baseRotationAngle: Double = 286
    private let jumpRotationAngle: Double = 290
    private let rotationsPerCycle = 5
    private var rotationAngleOffset: Double { (baseRotationAngle + jumpRotationAngle).truncatingRemainder(dividingBy: 360) }

    @State private var startTime = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: false)) { context in
            let now = context.date
            let elapsed = max(0, now.timeIntervalSince(startTime)) / max(speed, 0.0001)

            // Per-rotation timing
            let rDur = rotationDuration
            let rIndex = floor(elapsed / rDur)                   // 0,1,2...
            let localT = elapsed - rIndex * rDur                 // 0..rDur
            let f = localT / rDur                                // 0..1

            // Base rotation within this rotation (always forward)
            let base = f * baseRotationAngle

            // Head moves in first half, tail in second half (both strictly forward)
            let headPhase = min(f * 2, 1)                        // 0→1 over first half
            let tailPhase = max((f - 0.5) * 2, 0)                // 0→1 over second half

            let head = smooth(headPhase) * jumpRotationAngle     // degrees forward
            let tail = smooth(tailPhase) * jumpRotationAngle     // degrees forward

            // Arc
            let sweep = max(0.1, head - tail)                    // length; stays > 0
            let rotationOffset = (rIndex.truncatingRemainder(dividingBy: Double(rotationsPerCycle)) * rotationAngleOffset)
                .truncatingRemainder(dividingBy: 360)

            let startDeg = startAngleOffset + rotationOffset + base + tail

            Arc(startAngle: startDeg, sweep: sweep)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .accessibilityLabel("Loading")
        }
        .onAppear { startTime = Date() }
    }
    
    // Smooth easing (close to cubic-bezier(0.4,0,0.2,1), but simpler)
    func smooth(_ x: Double) -> Double { x*x*(3 - 2*x) } // smoothstep
}

private struct Arc: Shape {
    var startAngle: Double
    var sweep: Double
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c,
                 radius: r,
                 startAngle: .degrees(startAngle),
                 endAngle: .degrees(startAngle + sweep),
                 clockwise: false)
        return p
    }
}
