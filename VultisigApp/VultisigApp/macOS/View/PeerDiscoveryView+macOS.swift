//
//  PeerDiscoveryView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension PeerDiscoveryView {
    var content: some View {
        ZStack {
            GeometryReader { proxy in
                Background()
                    .onAppear {
                        setData(proxy)
                    }
            }
            
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            states
        }
    }
    
    var headerMac: some View {
        PeerDiscoveryHeader(
            vault: vault,
            selectedTab: selectedTab,
            viewModel: viewModel,
            shareSheetViewModel: shareSheetViewModel
        )
    }
    
    var landscapeContent: some View {
        HStack {
            qrCode
            
            VStack {
                vaultDetail
                list
            }
            .padding(40)
        }
    }
    
    var paringBarcode: some View {
        ZStack {
            qrCodeImage?
                .resizable()
                .background(Color.blue600)
                .frame(maxHeight: .infinity)
                .padding(3)
                .background(Color.neutral0)
                .cornerRadius(10)
                .padding()
                .background(Color.blue600)
                .cornerRadius(15)
                .overlay (
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [58]))
                )
                .padding(1)
                .aspectRatio(contentMode: .fit)
        }
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding(40)
    }
    
    var scrollList: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                devices
            }
            .padding(.horizontal, 30)
        }
        .padding(20)
    }
    
    var gridList: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                devices
            }
        }
        .scrollIndicators(.hidden)
    }
    
    var networkPrompts: some View {
        NetworkPrompts(selectedNetwork: $viewModel.selectedNetwork)
            .onChange(of: viewModel.selectedNetwork) {
                print("selected network changed: \(viewModel.selectedNetwork)")
                viewModel.restartParticipantDiscovery()
                setData()
            }
            .padding(.top, 10)
    }
    
    var devices: some View {
        ForEach(participantDiscovery.peersFound, id: \.self) { peer in
            Button {
                viewModel.handleSelection(peer)
            } label: {
                PeerCell(id: peer, isSelected: viewModel.selections.contains(peer))
            }
        }
    }
    
    var bottomButton: some View {
        Button(action: {
            viewModel.showSummary()
        }) {
            FilledButton(title: "continue")
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .disabled(disableContinueButton())
        .opacity(disableContinueButton() ? 0.8 : 1)
        .grayscale(disableContinueButton() ? 1 : 0)
        .padding(.bottom, 30)
    }
    
    func setData() {
        qrCodeImage = viewModel.getQrImage(size: 100)
        
        guard let qrCodeImage else {
            return
        }
        
        shareSheetViewModel.render(
            qrCodeImage: qrCodeImage,
            displayScale: displayScale,
            type: .Keygen
        )
    }
}
#endif
