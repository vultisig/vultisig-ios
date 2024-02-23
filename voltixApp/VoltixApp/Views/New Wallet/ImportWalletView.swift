import SwiftUI
import OSLog
import CodeScanner
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "import-wallet", category: "communication")
struct ImportWalletView: View {
    @Binding var presentationStack: [CurrentScreen]
    @State private var vaultText = ""
    @State private var errorMsg: String = ""
    @State private var isShowingScanner = false
    @State private var showingPicker = false
    @State private var pickedURLs: [URL] = []
    
    @State private var isShowingFileImporter = false
    
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading) {
                Spacer().frame(height: 30)
                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $vaultText)
                        .font(.custom("AmericanTypewriter", size: geometry.size.width * 0.05))
                        .scrollContentBackground(.hidden)
                        .frame(height: geometry.size.height * 0.4)
                        .padding()
                        .background(Color.primary.opacity(0.5))
                        .cornerRadius(12)
                    
                    HStack {
                        Button("", systemImage: "camera") {
                            self.isShowingScanner = true
                        }
                        .sheet(isPresented: self.$isShowingScanner, content: {
                            CodeScannerView(codeTypes: [.qr], completion: self.handleScan)
                        })
                        .padding(.trailing, 8)
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            isShowingFileImporter = true
                        }) {
                            Image(systemName: "doc.text.viewfinder")
                        }
                        .padding(.all, 20)
                        .buttonStyle(PlainButtonStyle())
                        .fileImporter(
                            isPresented: $isShowingFileImporter,
                            allowedContentTypes: [UTType.content], // Adjust based on the file types you want to allow
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                                case .success(let urls):
                                    guard let selectedFileURL = urls.first else { return }
                                    
                                    print(selectedFileURL)
                                        // Read the content of the file
                                    readContent(of: selectedFileURL)
                                case .failure(let error):
                                        // Handle the error
                                    print("Error selecting file: \(error.localizedDescription)")
                            }
                        }                    }
                }
                
                Text("ENTER YOUR PREVIOUSLY CREATED VAULT SHARE")
                    .font(.system(size: geometry.size.width * 0.04, weight: .medium))
                    .padding(.top, 8)
                
                
                Spacer()
                
                BottomBar(
                    content: "CONTINUE",
                    onClick: {
                        self.presentationStack.append(.newWalletInstructions)
                    }
                )
                .padding(.bottom)
            }
            .padding([.leading, .trailing], geometry.size.width * 0.05)
                // Conditionally apply navigationBarTitleDisplayMode for non-macOS targets
            .navigationTitle("IMPORT")
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    private func readContent(of url: URL) {
        let success = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard success else {
            print("Permission denied for accessing the file.")
            return
        }
        
        do {
            let fileContent = try String(contentsOf: url, encoding: .utf8)
            DispatchQueue.main.async {
                self.vaultText = fileContent
            }
        } catch {
            print("Failed to read file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.vaultText = "Failed to read file"
            }
        }
    }
    
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
            case .success(let result):
                let qrCodeResult = result.string
                self.vaultText = qrCodeResult
                self.isShowingScanner = false
                    //
                    //            let decoder = JSONDecoder()
                    //            if let data = qrCodeResult.data(using: .utf8) {
                    //                do {
                    //                    self.vaultText = String(contentsOf: qrCodeResult, encoding: .utf8)
                    //                    print(data)
                    //                } catch {
                    //                    logger.error("fail to decode keysign message,error:\(error.localizedDescription)")
                    //                    self.errorMsg = error.localizedDescription
                    //                }
                    //            }
            case .failure(let err):
                logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
    
    
}

#Preview {
    ImportWalletView(presentationStack: .constant([]))
}
