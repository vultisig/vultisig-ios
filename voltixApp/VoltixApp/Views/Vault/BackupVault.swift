//
//  BackupVault.swift
//  VoltixApp
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "backup-vault", category: "view")
struct BackupVault: View {
    @Binding var presentationStack: [CurrentScreen]
    let vault: Vault
    
    var body: some View {
        ScrollView {
            VStack {
                getVaultQRImage()
                    .resizable()
                    .scaledToFit()
                    .padding()
                HStack{
                    Button("Save As File", systemImage: "square.and.arrow.down", action: {
                        print("Backup")
                    })
                    Button("Save Image", systemImage: "square.and.arrow.down", action: {
                        print("Backup")
                    })
                }
            }
        }
    }
    
    private func getVaultQRImage() -> Image {
        let encoder = JSONEncoder()
        do {
            let result = try encoder.encode(vault)
            return Utils.getQrImage(data: result, size: 100)
            
        } catch {
            logger.error("fail to get vault backup QR image,error:\(error.localizedDescription)")
        }
        return Image(systemName: "xmark")
    }
}

#Preview {
    BackupVault(presentationStack: .constant([]), vault: Vault(name: "test"))
}
