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
    @State var bannerToRemove: Int?
    @State private var timer: Timer?
    
    @State var internalBanners: [Banner] = []
    
    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(internalBanners.enumerated()), id: \.element) { offset, banner in
                        let shouldRemove = bannerToRemove == offset
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
                        .animation(.linear(duration: 0.3), value: shouldRemove)
                        .id(offset)
                        .scrollTransition{ content, phase in
                            content
                                .scaleEffect(y: phase.isIdentity ? 1 : 0.7)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .scrollIndicators(.hidden)
            
            VaultBannerCarouselIndicators(
                currentIndex: $currentIndex,
                bannersCount: $bannersCount
            )
            .transition(.opacity)
            .animation(.easeInOut, value: bannersCount)
            .showIf(bannersCount > 1)
        }
        .onLoad {
            internalBanners = banners
            guard Set(internalBanners) != Set(banners) else { return }
            internalBanners = banners
        }
//        .onChange(of: banners) { _, newValue in
//            guard Set(internalBanners) != Set(newValue) else { return }
//            internalBanners = banners
//        }
        .onChange(of: internalBanners) { _, newValue in
            bannersCount = newValue.count
//            startTimer()
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: currentIndex) {
            withAnimation {
                guard currentIndex != -1 else { return }
                scrollPosition = currentIndex
            }
        }
        .onChange(of: scrollPosition) {
            if scrollPosition != currentIndex {
                withAnimation {
                    currentIndex = scrollPosition ?? 0
                    stopTimer()
                    startTimer()
                }
            }
        }
    }
    
    func removeBanner(_ banner: Banner) {
        print("Remove banner \(banner.id)")
        stopTimer()
        let nextIndex = currentIndex != 0 ? currentIndex - 1 : currentIndex + 1
        currentIndex = -1
        bannerToRemove = internalBanners.firstIndex(where: { $0.id == banner.id }) ?? 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            bannerToRemove = nil
            internalBanners.remove(at: bannerToRemove ?? 0)
            print("Internal banners", internalBanners)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                currentIndex = 0
                startTimer()
            }
            
//            onClose(banner)
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
                    currentIndex: $currentIndex
                )
            }
        }
    }
}

private struct VaultBannerCarouselIndicator: View {
    let indicatorIndex: Int
    @Binding var currentIndex: Int
    
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
