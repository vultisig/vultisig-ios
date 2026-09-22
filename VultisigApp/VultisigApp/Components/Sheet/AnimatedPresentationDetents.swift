//
//  AnimatedPresentationDetents.swift
//  VultisigApp
//
//  Surgical, reusable choreography for animating a sheet between presentation
//  detents. SwiftUI does NOT animate a `presentationDetents` change on its own:
//  switching the active detent snaps. To get a smooth height transition we
//  momentarily WIDEN the detent set to include both the current and the target
//  detents, yield one presentation update so the system registers that set,
//  switch the `selection` to the target (now an animatable move within the
//  wider set), then collapse the set after the move settles.
//
//  The host passes the `target` detent for its current sub-state; the modifier
//  re-runs the choreography whenever `target` changes. The animation `Task` is
//  cancelled on `onDisappear` so a sleeping task can't wake up and mutate the
//  selection after the sheet is gone.
//
//  Extracted from `VaultManagementSheet`'s `updateDetents` so other multi-state
//  sheets (Advanced Swap today; VaultManagementSheet could adopt it later) can
//  share the exact same timing without re-implementing it.
//

import SwiftUI

private struct AnimatedPresentationDetentsModifier: ViewModifier {
    private static var registrationDelay: Duration { .milliseconds(20) }
    private static var animationDuration: Double { 0.3 }
    private static var settleDelay: Duration { .milliseconds(350) }

    let target: PresentationDetent
    let alwaysAvailable: [PresentationDetent]
    let animatesFirstChange: Bool

    @State private var detents: Set<PresentationDetent>
    @State private var selection: PresentationDetent
    @State private var animationTask: Task<Void, Never>?
    @State private var hasChanged = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(target: PresentationDetent, alwaysAvailable: [PresentationDetent], animatesFirstChange: Bool) {
        self.target = target
        self.alwaysAvailable = alwaysAvailable
        self.animatesFirstChange = animatesFirstChange
        _detents = State(initialValue: Set([target] + alwaysAvailable))
        _selection = State(initialValue: target)
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents(detents, selection: $selection)
            .onChange(of: target) { _, newTarget in
                defer { hasChanged = true }
                guard animatesFirstChange || hasChanged else {
                    detents = Set([newTarget] + alwaysAvailable)
                    selection = newTarget
                    return
                }
                animate(to: newTarget)
            }
            .onDisappear {
                // Cancel the sleeping animation Task so it can't wake up and
                // mutate `selection` after the sheet has been dismissed.
                animationTask?.cancel()
                animationTask = nil
            }
    }

    /// Move between two registered detents without a second, delayed layout
    /// animation:
    /// 1. Widen the set to include both current and target (so the move can animate).
    /// 2. On the next presentation update, switch the selection to the target.
    /// 3. Collapse the set back to just the target after the native move settles.
    private func animate(to newTarget: PresentationDetent) {
        animationTask?.cancel()

        guard newTarget != selection else {
            detents = Set([newTarget] + alwaysAvailable)
            return
        }

        guard !reduceMotion else {
            detents = Set([newTarget] + alwaysAvailable)
            selection = newTarget
            return
        }

        // Widen to include both the current selection and the new target plus
        // any always-available detents, so the upcoming selection change is an
        // animatable move inside the wider set rather than a snap.
        detents = Set([selection, newTarget] + alwaysAvailable)

        animationTask = Task { @MainActor in
            // A single run-loop yield is usually enough. The short fallback
            // delay also covers the first update on slower presentation hosts.
            await Task.yield()
            try? await Task.sleep(for: Self.registrationDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Self.animationDuration)) {
                selection = newTarget
            }
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            detents = Set([newTarget] + alwaysAvailable)
        }
    }
}

extension View {
    /// Animate the sheet to `target` whenever it changes, using the widen → wait
    /// → switch → wait → collapse choreography that SwiftUI's bare
    /// `presentationDetents` won't perform on its own.
    ///
    /// - Parameters:
    ///   - target: the detent for the host's current sub-state. Changing it
    ///     animates the sheet to the new height.
    ///   - alwaysAvailable: detents kept in the set at all times (e.g. a
    ///     drag-to-`.large` affordance) regardless of the current target.
    ///   - animatesFirstChange: `false` applies the first change at once, for
    ///     a sheet whose starting target is a placeholder it replaces before it
    ///     is on screen, such as a height it has yet to measure.
    func animatedPresentationDetents(
        target: PresentationDetent,
        alwaysAvailable: [PresentationDetent] = [],
        animatesFirstChange: Bool = true
    ) -> some View {
        modifier(AnimatedPresentationDetentsModifier(
            target: target,
            alwaysAvailable: alwaysAvailable,
            animatesFirstChange: animatesFirstChange
        ))
    }
}

#Preview {
    struct PreviewContainer: View {
        @State private var isPresented = true
        @State private var expanded = false

        var body: some View {
            Color.clear
                .sheet(isPresented: $isPresented) {
                    VStack(spacing: 24) {
                        Text(expanded ? "Expanded" : "Collapsed")
                            .font(Theme.fonts.title2)
                            .foregroundStyle(Theme.colors.textPrimary)

                        PrimaryButton(title: expanded ? "Collapse" : "Expand") {
                            withAnimation { expanded.toggle() }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Theme.colors.bgPrimary)
                    .animatedPresentationDetents(
                        target: expanded ? .large : .height(220),
                        alwaysAvailable: []
                    )
                }
        }
    }

    return PreviewContainer()
}
