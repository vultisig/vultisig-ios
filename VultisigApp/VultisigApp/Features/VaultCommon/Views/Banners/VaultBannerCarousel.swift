//
//  VaultBannerCarousel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import SwiftUI

protocol CarouselBannerType: Identifiable {
    var title: String { get }
    var subtitle: String { get }
    var buttonTitle: String { get }
}

enum VaultBannerType: String, CarouselBannerType {
    case upgradeVault, backupVault, followVultisig
    
    var id: String {
        rawValue
    }

    var title: String {
        "Test"
    }
    var subtitle: String {
        "Test"
    }
    var buttonTitle: String {
        "Test"
    }
}

struct BannerCarousel<Banner: CarouselBannerType>: View {
    
    @Binding var banners: [Banner]
    var onBanner: (Banner) -> Void
    var onClose: (Banner) -> Void
    
    @State var currentIndex: Int = 0
    @State var bannersCount: Int = 5
    @State private var timer: Timer?
    
    @State var internalBanners: [Banner] = []
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(internalBanners) { banner in
                    VaultBannerView(
                        title: banner.title,
                        subtitle: banner.subtitle,
                        buttonTitle: banner.buttonTitle,
                        bgImage: "referral-banner-2",
                        action: { onBanner(banner) },
                        onClose: { removeBanner(banner) }
                    )
                }
            }
            
            VaultBannerCarouselIndicators(
                currentIndex: $currentIndex,
                bannersCount: $bannersCount
            )
        }
        .onLoad {
            internalBanners = banners
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    func removeBanner(_ banner: Banner) {
        internalBanners.removeAll(where: { $0.id == banner.id })
        onClose(banner)
    }
    
    private func startTimer() {
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

struct VaultBannerCarouselIndicators: View {
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

struct VaultBannerCarouselIndicator: View {
    let indicatorIndex: Int
    @Binding var currentIndex: Int
    
    @State var isActive: Bool = false
    @State var progress: CGFloat = 0
    
    let capsuleWidth: CGFloat = 20
    let animation: Animation = .interpolatingSpring(mass: 1, stiffness: 100, damping: 15)
    
    var body: some View {
        Capsule()
            .fill(Theme.colors.bgSecondary)
            .frame(width: isActive ? capsuleWidth : 4, height: 4)
            .padding(.horizontal, 0.1)
            .overlay(isActive ? overlayView : nil, alignment: .leading)
            .onLoad {
                updateIsActive()
            }
            .onChange(of: currentIndex) { _, _ in
                updateIsActive()
            }
    }
    
    var overlayView: some View {
        Capsule()
            .fill(Theme.colors.textLight)
            .frame(width: progress, height: 4.1)
            .onAppear {
                withAnimation(.linear(duration: 2.5).delay(0.5)) {
                    progress = capsuleWidth
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
