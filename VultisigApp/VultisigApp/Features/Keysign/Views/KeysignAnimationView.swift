//
//  KeysignAnimationView.swift
//  VultisigApp
//

import OSLog
import SwiftUI
import RiveRuntime

private let logger = Logger(subsystem: "com.vultisig.app", category: "keysign-animation")

struct KeysignAnimationView: View {

    @Binding var connected: Bool
    var coinLogo: String?
    /// Signing progress on a 0–100 scale, bound to the Rive `progessPercentage`
    /// property so the bar fills as signing advances. Defaults to 0.
    var progress: Float = 0

    @State private var animationVM: RiveViewModel?
    @State private var animationVMInstance: RiveDataBindingViewModel.Instance?
    @State private var coinLogoTask: Task<Void, Never>?
    @State private var displayedProgress: Float = 0
    @State private var progressAnimationTimer: Timer?

    var body: some View {
        ZStack {
            animationVM?.view()
        }
        .ignoresSafeArea()
        .readSize { size in
            animationVMInstance?.numberProperty(fromPath: "posXcircles")?.value = Float(size.width / 2)
        }
        .onChange(of: connected) { _, newValue in
            animationVMInstance?.booleanProperty(fromPath: "Connected")?.value = newValue
        }
        .onChange(of: coinLogo) { _, newValue in
            applyCoinLogo(newValue)
        }
        .onChange(of: progress) { _, newValue in
            animateProgress(to: newValue)
        }
        .onAppear {
            setupAnimation()
        }
        .onDisappear {
            animationVM?.stop()
            coinLogoTask?.cancel()
            progressAnimationTimer?.invalidate()
            progressAnimationTimer = nil
        }
    }

    private func setupAnimation() {
        guard animationVM == nil else { return }
        let vm = RiveViewModel(fileName: "keysign", autoPlay: true)
        vm.fit = .layout
        vm.layoutScaleFactor = RiveViewModel.layoutScaleFactorAutomatic
        vm.riveModel?.enableAutoBind { instance in
            // Rive does not guarantee callbacks land on the main actor.
            Task { @MainActor in
                animationVMInstance = instance
                instance.booleanProperty(fromPath: "Connected")?.value = connected
                applyCoinLogo(coinLogo)
                displayedProgress = progress
                updateRiveProgress(progress)
            }
        }
        animationVM = vm
    }

    private func animateProgress(to targetValue: Float) {
        progressAnimationTimer?.invalidate()

        let duration: TimeInterval = 1.0
        let frameRate: TimeInterval = 1.0 / 60.0
        let totalSteps = Int(duration / frameRate)
        let startValue = displayedProgress
        let delta = targetValue - startValue

        guard delta != 0, totalSteps > 0 else {
            displayedProgress = targetValue
            updateRiveProgress(targetValue)
            return
        }

        var currentStep = 0

        progressAnimationTimer = Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true) { timer in
            currentStep += 1
            let stepProgress = Float(currentStep) / Float(totalSteps)
            let easedProgress = 1 - pow(1 - stepProgress, 3)
            let newValue = startValue + delta * easedProgress

            displayedProgress = newValue
            updateRiveProgress(newValue)

            if currentStep >= totalSteps {
                timer.invalidate()
                progressAnimationTimer = nil
                displayedProgress = targetValue
                updateRiveProgress(targetValue)
            }
        }
    }

    private func updateRiveProgress(_ value: Float) {
        animationVMInstance?.numberProperty(fromPath: "progessPercentage")?.value = value
    }

    private func applyCoinLogo(_ logo: String?) {
        coinLogoTask?.cancel()
        guard let logo, !logo.isEmpty,
              let instance = animationVMInstance,
              let property = instance.imageProperty(fromPath: "toToken") else {
            return
        }

        coinLogoTask = Task { @MainActor in
            guard let data = await imageData(for: logo) else {
                logger.warning("No image data for coin logo \(logo, privacy: .public); leaving toToken unset")
                return
            }
            guard !Task.isCancelled else { return }
            guard let renderImage = RiveRenderImage(data: data) else {
                logger.warning("RiveRenderImage init returned nil for \(logo, privacy: .public)")
                return
            }
            guard !Task.isCancelled else { return }
            property.setValue(renderImage)
        }
    }

    private func imageData(for logo: String) async -> Data? {
        if logo.hasPrefix("https://"), let url = URL(string: logo) {
            return await remoteImageData(url: url)
        }
        return localAssetPNGData(named: logo)
    }

    private func remoteImageData(url: URL) async -> Data? {
        // URLCache.cachedResponse(for:) requires a request as the cache key;
        // not a typed HTTP call.
        // swiftlint:disable:next no_raw_urlrequest
        let request = URLRequest(url: url)
        if let cached = URLCache.imageCache.cachedResponse(for: request) {
            return cached.data
        }
        do {
            // swiftlint:disable:next no_raw_urlsession
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                logger.warning("Non-success response for coin logo \(url.absoluteString, privacy: .public)")
                return nil
            }
            URLCache.imageCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            return data
        } catch {
            logger.warning("Failed to fetch coin logo from \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func localAssetPNGData(named assetName: String) -> Data? {
        #if os(iOS)
        return UIImage(named: assetName)?.pngData()
        #elseif os(macOS)
        guard let image = NSImage(named: assetName),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}
