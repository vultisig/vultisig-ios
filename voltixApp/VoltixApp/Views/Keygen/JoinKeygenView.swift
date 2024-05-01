//
//  JoinKeygen.swift
//  VoltixApp

import CodeScanner
import Network
import OSLog
import SwiftUI
import UniformTypeIdentifiers

import UIKit
import CoreImage
import Vision

struct JoinKeygenView: View {
    let vault: Vault
    
    @StateObject var viewModel = JoinKeygenViewModel()
    @StateObject var serviceDelegate = ServiceDelegate()
    @State var showFileImporter = false
    
    let logger = Logger(subsystem: "join-keygen", category: "communication")
    
    var body: some View {
        ZStack {
            Background()
            states
        }
        .navigationTitle(NSLocalizedString("joinKeygen", comment: "Join keygen/reshare"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.image], // Ensure only images can be picked
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let success = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                
                guard success else {
                    print("Failed to access URL")
                    return
                }
                
                // Attempt to create a UIImage from the contents of the URL
                if let imageData = try? Data(contentsOf: url),
                   let selectedImage = UIImage(data: imageData) {
                    let qrStrings = detectQRCode(selectedImage)
                    if qrStrings.isEmpty {
                        print("No QR codes detected.")
                    } else {
                        for qrString in qrStrings {
                            print("Detected QR code with data: \(qrString)")
                        }
                    }
                } else {
                    print("Failed to load image from URL")
                }
                
            case .failure(let error):
                print("Error selecting file: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $viewModel.isShowingScanner, content: {
            CodeScannerView(codeTypes: [.qr], completion: self.viewModel.handleScan)
        })
        .onAppear {
            viewModel.setData(vault: vault, serviceDelegate: self.serviceDelegate)
        }
        .onDisappear {
            viewModel.stopJoinKeygen()
        }
    }
    
    var states: some View {
        VStack {
            switch viewModel.status {
            case .DiscoverSessionID:
                discoveringSessionID
            case .DiscoverService:
                discoveringService
            case .JoinKeygen:
                joinKeygen
            case .WaitingForKeygenToStart:
                waitingForKeygenStart
            case .KeygenStarted:
                keygenStarted
            case .FailToStart:
                failToStartKeygen
            }
        }
        .padding()
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    var scanButton: some View {
        ZStack {
            Circle()
                .foregroundColor(.turquoise600)
                .frame(width: 60, height: 60)
            
            Image(systemName: "camera")
                .font(.title30MenloUltraLight)
                .foregroundColor(.blue600)
        }
    }
    
    var keygenStarted: some View {
        HStack {
            if viewModel.serverAddress != nil && self.viewModel.sessionID != nil {
                keygenView
            } else {
                keygenErrorText
            }
        }
        .padding(.vertical, 30)
    }
    
    var keygenView: some View {
        KeygenView(
            vault: vault,
            tssType: self.viewModel.tssType,
            keygenCommittee: self.viewModel.keygenCommittee,
            vaultOldCommittee: self.viewModel.oldCommittee.filter { self.viewModel.keygenCommittee.contains($0) },
            mediatorURL: viewModel.serverAddress!,
            sessionID: self.viewModel.sessionID!,
            encryptionKeyHex: viewModel.encryptionKeyHex)
    }
    
    var keygenErrorText: some View {
        Text(NSLocalizedString("failToStartKeygen", comment: "Unable to start key generation due to missing information"))
            .font(.body15MenloBold)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
    
    var failToStartKeygen: some View {
        VStack{
            Text(viewModel.errorMessage)
                .font(.body15MenloBold)
                .multilineTextAlignment(.center)
                .padding(.vertical, 30)
            
            filePicker
        }
    }
    
    var discoveringSessionID: some View {
        ProgressView()
            .preferredColorScheme(.dark)
            .onAppear {
                viewModel.showBarcodeScanner()
            }
    }
    
    var discoveringService: some View {
        VStack {
            HStack {
                Text(NSLocalizedString("thisDevice", comment: "This device"))
                Text(self.viewModel.localPartyID)
            }
            
            HStack {
                Text(NSLocalizedString("discoveringMediator", comment: "Discovering mediator service, please wait..."))
                
                if serviceDelegate.serverURL == nil {
                    ProgressView().progressViewStyle(.circular).padding(2)
                } else {
                    Image(systemName: "checkmark")
                        .onAppear {
                            viewModel.serverAddress = serviceDelegate.serverURL!
                            viewModel.setStatus(status: .JoinKeygen)
                        }
                }
            }
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(.vertical, 30)
        .onAppear {
            logger.info("Start to discover service")
            viewModel.discoverService()
        }
    }
    
    var joinKeygen: some View {
        VStack {
            HStack {
                Text("thisDevice")
                Text(self.viewModel.localPartyID)
            }
            
            HStack {
                Text(NSLocalizedString("joinKeygen", comment: "Joining key generation, please wait..."))
                    .onAppear {
                        viewModel.joinKeygenCommittee()
                    }
            }
        }
        .font(.body15MenloBold)
        .multilineTextAlignment(.center)
        .padding(.vertical, 30)
    }
    
    var filePicker: some View {
        Button {
            print("Toggling file importer")
            showFileImporter.toggle()
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var waitingForKeygenStart: some View {
        VStack {
            HStack {
                Text("thisDevice")
                Text(self.viewModel.localPartyID)
            }
            
            HStack {
                Text(NSLocalizedString("waitingForKeygenStart", comment: "Waiting for key generation to start..."))
                ProgressView().progressViewStyle(.circular).padding(2)
            }
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(.vertical, 30)
        .task {
            await viewModel.waitForKeygenStart()
        }
    }
    
    func detectQRCode(_ image: UIImage?) -> [String] {
        var detectedStrings = [String]()
        guard let image = image, let ciImage = CIImage(image: image) else { return detectedStrings }
        
        let context = CIContext()
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options)
        
        if let features = qrDetector?.features(in: ciImage) {
            for feature in features as! [CIQRCodeFeature] {
                if let decodedString = feature.messageString {
                    detectedStrings.append(decodedString)
                }
            }
        }
        
        return detectedStrings
    }
    
}

struct JoinKeygenView_Previews: PreviewProvider {
    static var previews: some View {
        JoinKeygenView(vault: Vault.example)
    }
}
