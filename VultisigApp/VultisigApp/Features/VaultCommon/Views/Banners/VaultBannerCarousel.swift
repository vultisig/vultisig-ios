//
//  VaultBannerCarousel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import SwiftUI

struct BannerCarousel<Banner: CarouselBannerType>: View {
    
    @Binding var banners: [Banner]
    var onBanner: (Banner) -> Void
    var onClose: (Banner) -> Void
    
    @State var currentIndex: Int = 0
    @State var scrollPosition: Int? = 0
    @State var bannersCount: Int = 0
    @State var bannersToRemove: Set<AnyHashable> = []
    @State private var timer: Timer?
    
    @State var internalBanners: [Banner] = []
    
    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(internalBanners.indices, id: \.self) { index in
                        let banner = internalBanners[index]
                        let shouldRemove = bannersToRemove.contains(AnyHashable(banner.id)) && banners.count > 0
                        VaultBannerView(
                            title: banner.title,
                            subtitle: banner.subtitle,
                            buttonTitle: banner.buttonTitle,
                            bgImage: "referral-banner-2",
                            action: { onBanner(banner) },
                            onClose: { removeBanner(banner) }
                        )
                        .frame(width: shouldRemove ? 0 : 345, height: 128, alignment: .leading)
                        .opacity(shouldRemove ? 0 : 1)
                        .scaleEffect(x: shouldRemove ? 0.8 : 1.0)
                        .animation(.easeInOut(duration: 0.4), value: shouldRemove)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(y: phase.isIdentity ? 1 : 0.7)
                        }
                        .id(banner.id)
                    }
                }
                .scrollTargetLayout()
                .animation(.easeInOut(duration: 0.3), value: internalBanners.count)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .scrollIndicators(.hidden)
            
            VaultBannerCarouselIndicators(
                currentIndex: $currentIndex,
                bannersCount: $bannersCount
            )
            .id(internalBanners.count)
            .transition(.verticalGrowAndFade)
            .animation(.easeInOut, value: bannersCount)
            .showIf(bannersCount > 1)
        }
        .frame(height: 4 + 12 + 128)
        .onLoad {
            internalBanners = banners
        }
        .onChange(of: banners) { _, newValue in
            guard Set(internalBanners) != Set(newValue), newValue.count > 0 else { return }
            internalBanners = banners
        }
        .onChange(of: internalBanners) { _, newValue in
            bannersCount = newValue.count
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
            }
        }
    }
    
    func removeBanner(_ banner: Banner) {
        stopTimer()
        
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
}

private struct VaultBannerCarouselIndicators: View {
    @Binding var currentIndex: Int
    @Binding var bannersCount: Int
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bannersCount, id: \.self) { index in
                VaultBannerCarouselIndicator(
                    indicatorIndex: index,
                    currentIndex: $currentIndex,
                    bannersCount: bannersCount
                )
            }
        }
    }
}

private struct VaultBannerCarouselIndicator: View {
    let indicatorIndex: Int
    @Binding var currentIndex: Int
    let bannersCount: Int
    
    @State var isActive: Bool = false
    @State var progress: CGFloat = 0
    
    let capsuleWidth: CGFloat = 20
    let animation: Animation = .interpolatingSpring(mass: 1, stiffness: 100, damping: 15)
    
    var body: some View {
        Capsule()
            .fill(Theme.colors.bgTertiary)
            .frame(width: isActive ? capsuleWidth : 4, height: 4)
            .padding(.horizontal, 0.1)
            .overlay(isActive ? overlayView : nil, alignment: .leading)
            .onLoad {
                updateIsActive()
            }
            .onChange(of: currentIndex) {
                updateIsActive()
            }
    }
    
    var overlayView: some View {
        Capsule()
            .fill(Theme.colors.textLight)
            .frame(width: progress, height: 4.1)
            .offset(x: -1)
            .onAppear {
                withAnimation(.linear(duration: 2.5).delay(0.5)) {
                    progress = capsuleWidth + 1
                }
            }
    }
    
    func updateIsActive() {
        withAnimation(animation) {
            isActive = currentIndex == indicatorIndex
            if !isActive {
                progress = 0
            }
        }
    }
}

#Preview {
    @Previewable @State var banners = [VaultBannerType.upgradeVault, .backupVault, .followVultisig]
    
    BannerCarousel(
        banners: $banners,
        onBanner: { _ in },
        onClose: { _ in }
    )
}
