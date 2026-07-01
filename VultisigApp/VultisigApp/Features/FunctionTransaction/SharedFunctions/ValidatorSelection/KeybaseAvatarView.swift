//
//  KeybaseAvatarView.swift
//  VultisigApp
//
//  Validator avatar component used by the active-delegations card and the
//  validator picker. Renders the deterministic colored-initial monogram
//  while the Keybase URL lookup is in flight; swaps in the remote avatar
//  via `CachedAsyncImage` when resolved; stays on the monogram when the
//  identity is `nil` or the lookup returns no URL.
//
//  Resolves through the shared `KeybaseAvatarService` actor — same 1-hour
//  TTL as Windows' `useKeybaseAvatarQuery`, with the lookup coalesced
//  across views so re-rendering the validator list doesn't multiply
//  outbound requests.
//

import SwiftUI

struct KeybaseAvatarView: View {
    let identity: String?
    let monogram: String
    let size: CGFloat
    var service: KeybaseAvatarServiceProtocol = KeybaseAvatarStore.shared.service

    @State private var resolvedURL: URL?
    @State private var didAttemptLookup = false

    var body: some View {
        ZStack {
            monogramAvatar
            if let url = resolvedURL {
                CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .task(id: identity) {
            guard let identity, !identity.isEmpty, !didAttemptLookup else { return }
            didAttemptLookup = true
            resolvedURL = await service.avatarURL(forIdentity: identity)
        }
    }

    private var monogramAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.colors.primaryAccent3, Theme.colors.primaryAccent4],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(monogram)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
}

/// Process-wide store for the Keybase avatar service so successive
/// `KeybaseAvatarView` instances share the 1-hour cache instead of each
/// holding their own. Mirrors the implicit `QueryClient` shape that
/// `useKeybaseAvatarQuery` benefits from on Windows.
enum KeybaseAvatarStore {
    static let shared = Container()

    final class Container {
        let service: KeybaseAvatarServiceProtocol = KeybaseAvatarService()
    }
}
