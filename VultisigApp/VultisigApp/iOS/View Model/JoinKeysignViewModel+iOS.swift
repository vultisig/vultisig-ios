//
//  JoinKeysignViewModel+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension JoinKeysignViewModel {
    func handleScan(result: Result<ScanResult, ScanError>) {
        defer {
            self.isShowingScanner = false
        }
        
        guard let isCameraPermissionGranted, isCameraPermissionGranted else {
            status = .KeysignNoCameraAccess
            return
        }
        
        switch result {
        case .success(let result):
            guard let data = DeeplinkViewModel.getJsonData(URL(string: result.string)) else {
                return
            }
            Task{
                await handleQrCodeSuccessResult(data: data)
                DispatchQueue.main.async {
                    self.manageQrCodeStates()
                }
            }
        case .failure(let err):
            self.errorMsg = "QR code scanning failed: \(err.localizedDescription)"
            self.status = .FailedToStart
        }
        
        
    }
}
#endif
