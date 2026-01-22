//
//  BannerCarousel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import SwiftUI

struct BannersCarousel<Banner: CarouselBannerType>: View {
    @Binding var banners: [Banner]
    let availableWidth: CGFloat
    /// Used for VStack spacing
    let paddingTop: CGFloat?
    var onBanner: (Banner) -> Void
    var onClose: (Banner) -> Void

    @State var currentIndex: Int = 0
    @State var scrollPosition: Int? = 0
    @State var bannersCount: Int = 0
    @State var bannersToRemove: Set<AnyHashable> = []
    @State private var timer: Timer?
    @State var showCarousel: Bool = false

    @State var internalBanners: [Banner] = []

    var bannerWidth: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return availableWidth - spacing * 2
        } else {
            return BannerLayoutProperties.maxWidth
        }
        #else
        return BannerLayoutProperties.maxWidth
        #endif
    }

    var horizontalPadding: CGFloat {
        max((availableWidth - bannerWidth) / 2, BannerLayoutProperties.minimumPadding)
    }

    private let bannerHeight: CGFloat = 128
    private let spacing: CGFloat = 16
    private let indicatorsHeight: CGFloat = BannerLayoutProperties.indicatorsHeight

    var body: some View {
        ZStack {
            VStack(spacing: spacing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(internalBanners.indices, id: \.self) { index in
                            let banner = internalBanners[index]
                            let shouldRemove = bannersToRemove.contains(AnyHashable(banner.id)) && !banners.isEmpty
                            VStack {
                                CarouselBannerView(
                                    banner: banner,
                                    action: { onBanner(banner) },
                                    onClose: { removeBanner(banner) }
                                )
                                .frame(width: bannerWidth, height: bannerHeight, alignment: .leading)
                            }
                            .padding(.horizontal, spacing)
                            .frame(width: availableWidth, alignment: .center)
                            .opacity(shouldRemove ? 0 : 1)
                            .animation(.easeInOut(duration: 0.4), value: shouldRemove)
                            .scrollTransition { content, phase in
                                content
                                    .scaleEffect(y: phase.isIdentity ? 1 : 0.8)
                            }
                            .id(banner.id)
                        }
                    }
                    .scrollTargetLayout()
                    .animation(.easeInOut(duration: 0.3), value: internalBanners.count)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollPosition, anchor: .center)
                .scrollIndicators(.never)

                VaultBannerCarouselIndicators(
                    currentIndex: $currentIndex,
                    bannersCount: $bannersCount
                )
                .transition(.verticalGrowAndFade)
                .animation(.easeInOut, value: bannersCount)
                .showIf(bannersCount > 1)
            }
            .unwrap(paddingTop) { $0.padding(.top, $1) }
            .transition(.verticalGrowAndFade)
            .showIf(showCarousel)
        }
        .onLoad {
            internalBanners = banners
        }
        .onChange(of: banners) { _, newValue in
            guard Set(internalBanners) != Set(newValue) else { return }
            internalBanners = banners
        }
        .onChange(of: internalBanners) { _, newValue in
            updateBannersCount(newValue.count)
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: currentIndex) {
            withAnimation {
                guard currentIndex >= 0 && currentIndex < internalBanners.count else { return }
                scrollPosition = currentIndex
            }
        }
        .onChange(of: scrollPosition) {
            guard let newScrollPosition = scrollPosition else {
                return
            }

            withAnimation {
                currentIndex = newScrollPosition
                startTimer()
            }
        }
    }

    func removeBanner(_ banner: Banner) {
        stopTimer()

        if bannersCount == 1 {
            updateBannersCount(0)
        }

        guard let indexToRemove = internalBanners.firstIndex(where: { $0.id == banner.id }) else {
            print("Banner not found")
            return
        }

        // Calculate the new current index before removal
        let newCurrentIndex: Int
        if internalBanners.count <= 1 {
            newCurrentIndex = 0
        } else if indexToRemove < currentIndex {
            // If we're removing a banner before current position
            newCurrentIndex = currentIndex - 1
        } else if indexToRemove == currentIndex {
            // If we're removing the current banner
            if indexToRemove == internalBanners.count - 1 {
                // If it's the last banner, go to previous
                newCurrentIndex = max(0, currentIndex - 1)
            } else {
                // Otherwise stay at same index (next banner will slide into position)
                newCurrentIndex = currentIndex
            }
        } else {
            // If we're removing a banner after current position
            newCurrentIndex = currentIndex
        }

        // Start the removal animation
        _ = withAnimation(.easeInOut(duration: 0.4)) {
            bannersToRemove.insert(AnyHashable(banner.id))
        }

        // Wait for removal animation to complete, then update the data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Remove the banner from the array
            internalBanners.removeAll { $0.id == banner.id }
            bannersToRemove.remove(AnyHashable(banner.id))

            // Update indices without animation to prevent conflicts
            if !internalBanners.isEmpty {
                let safeIndex = min(max(0, newCurrentIndex), internalBanners.count - 1)
                currentIndex = safeIndex
                scrollPosition = safeIndex
            } else {
                currentIndex = 0
                scrollPosition = 0
            }

            // Restart timer after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !internalBanners.isEmpty {
                    startTimer()
                }
            }

            // Notify parent that banner was removed
            onClose(banner)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                if currentIndex < bannersCount - 1 {
                    currentIndex += 1
                } else {
                    currentIndex = 0
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateBannersCount(_ count: Int) {
        let shouldShow = count > 0
        withAnimation(.easeInOut) {
            showCarousel = shouldShow
            bannersCount = count
        }
    }
}

#Preview {
    @Previewable @State var banners = [VaultBannerType.upgradeVault, .backupVault, .followVultisig]

    BannersCarousel(
        banners: $banners,
        availableWidth: 500,
        paddingTop: nil,
        onBanner: { _ in },
        onClose: { _ in }
    )
}
