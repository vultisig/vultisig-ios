//
//  VaultPairDetailView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//
import Foundation
import SwiftUI

struct VaultPairDetailView: View {
    let vault: Vault
    let devicesInfo: [DeviceInfo]

    @State var deviceIndex: Int = 0
    @State var showCapsule: Bool = false
    @State var imageName = ""

    @StateObject var viewModel = VaultPairDetailViewModel()
    @Environment(\.displayScale) var displayScale

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    VaultPairDetailCard(
                        vault: vault,
                        devicesInfo: devicesInfo,
                        isForSharing: false,
                        onKeyCopy: { showCapsule = true }
                    )
                }
            }
        }
        .screenTitle("vaultDetailsTitle".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                if let renderedImage = viewModel.renderedImage {
                    CrossPlatformShareButton(image: renderedImage, caption: imageName) { onShare in
                        ToolbarButton(image: "share", action: onShare)
                    }
                } else {
                    ProgressView()
                        .frame(width: 20, height: 20)
                }
            }
        }
        .overlay(PopupCapsule(text: "keyCopied", showPopup: $showCapsule))
        .onLoad {
            imageName = viewModel.generateName(vault: vault)
            viewModel.render(vault: vault, devicesInfo: devicesInfo, displayScale: displayScale)
        }
    }
}

#Preview {
    VaultPairDetailView(vault: Vault.example, devicesInfo: [])
}
