//
//  KeysignReviewPresenter.swift
//  VultisigApp
//

import Foundation

/// Owns the one keysign review sheet and hands its sign step to the
/// navigation stack.
///
/// A sheet cannot push over itself, so `proceed(to:)` only records the
/// signing route and closes the sheet. The host pushes the route from the
/// sheet's `onDismiss`, once the dismissal has settled: pushing while the
/// sheet is still on screen races the dismissal and the push can be dropped.
@MainActor
@Observable
final class KeysignReviewPresenter {
    /// The review on screen. Drives the host's sheet, which clears it when the
    /// user dismisses the sheet.
    var presented: KeysignReview?

    /// Stamps each presentation. The review content hands back the one it was
    /// shown under, so a sign step that finishes after its review has gone
    /// cannot proceed a later one.
    private(set) var presentationID = UUID()

    /// Raised by `reopenForRetry()` until the host brings the review back.
    private(set) var isReopenPending = false

    /// The review that started the current signing flow, for a retry.
    private var lastReview: KeysignReview?
    /// Pushed once the sheet has closed.
    private var pendingRoute: SigningRoute?

    /// A review is on screen, or its sheet is still closing towards a push.
    var isPresenting: Bool {
        presented != nil || pendingRoute != nil
    }

    /// Ignored while a review is presenting: a second review would replace the
    /// one the user is reading, or land under a signing push.
    func present(_ review: KeysignReview) {
        guard !isPresenting else { return }
        lastReview = review
        if isReopenPending {
            isReopenPending = false
        }
        presentationID = UUID()
        presented = review
    }

    /// Closes the review and queues `route` for the host to push once the
    /// sheet is gone. Ignored unless `presentationID` is the presentation on
    /// screen, so a sign step that finishes after the user dismissed its
    /// review starts nothing.
    func proceed(to route: SigningRoute, presentationID: UUID) {
        guard presented != nil, presentationID == self.presentationID else { return }
        pendingRoute = route
        presented = nil
    }

    /// Closes the review without signing, as its close button does.
    func dismiss() {
        guard presented != nil else { return }
        presented = nil
    }

    /// Called from the sheet's `onDismiss`. Pushes the queued route, if the
    /// review ended by proceeding rather than by being dismissed.
    func sheetDidDismiss(router: NavigationRouter) {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        router.navigate(to: route)
    }

    /// Asks for the last review to come back after a retryable signing
    /// failure. The host presents it once the stack is out of signing; see
    /// `completeReopen(isShowingSigningRoute:)`.
    func reopenForRetry() {
        guard lastReview != nil, !isPresenting else { return }
        isReopenPending = true
    }

    /// Presents the last review again, provided a reopen is pending and the
    /// signing screens are off the stack.
    func completeReopen(isShowingSigningRoute: Bool) {
        guard isReopenPending, !isShowingSigningRoute else { return }
        isReopenPending = false
        guard let lastReview else { return }
        present(lastReview)
    }

    /// The signing flow reached its end; there is nothing left to retry.
    func flowFinished() {
        lastReview = nil
        if isReopenPending {
            isReopenPending = false
        }
    }
}
