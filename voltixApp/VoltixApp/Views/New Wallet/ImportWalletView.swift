import CodeScanner
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "import-wallet", category: "communication")
struct ImportWalletView: View {
    @Binding var presentationStack: [CurrentScreen]
    @Environment(\.modelContext) private var context
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
                    TextEditor(text: self.$vaultText)
                        .font(.custom("AmericanTypewriter", size: geometry.size.width * 0.05))
                        .scrollContentBackground(.hidden)
                        .frame(height: geometry.size.height * 0.4)
                        .padding()
                        .background(Color.primary.opacity(0.5))
                        .cornerRadius(12)
                    
                    HStack {
                        Button(action: {
                            self.isShowingFileImporter = true
                        }) {
                            Image(systemName: "doc.text.viewfinder")
                        }
                        .padding(.all, 20)
                        .buttonStyle(PlainButtonStyle())
                        .fileImporter(
                            isPresented: self.$isShowingFileImporter,
                            allowedContentTypes: [UTType.data], // Adjust based on the file types you want to allow
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                                case .success(let urls):
                                    guard let selectedFileURL = urls.first else { return }
                                    
                                    print(selectedFileURL)
                                    // Read the content of the file
                                    self.readContent(of: selectedFileURL)
                                case .failure(let error):
                                    // Handle the error
                                    print("Error selecting file: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                Text("ENTER YOUR PREVIOUSLY CREATED VAULT SHARE")
                    .font(.system(size: geometry.size.width * 0.04, weight: .medium))
                    .padding(.top, 8)
                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.system(size: geometry.size.width * 0.04, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }
                Spacer()
                
                BottomBar(
                    content: "CONTINUE",
                    onClick: {
                        if restoreVault(hexVaultData: vaultText, modelContext: context) {
                            self.presentationStack.append(.vaultSelection)
                        }
                    }
                )
                .padding(.bottom)
            }
            .padding([.leading, .trailing], geometry.size.width * 0.05)
            // Conditionally apply navigationBarTitleDisplayMode for non-macOS targets
            .navigationTitle("IMPORT")
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
        }
    }

    private func readContent(of url: URL) {
        let success = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard success else {
            errorMsg = "Permission denied for accessing the file."
            return
        }
        
        do {
            let fileContent = try String(contentsOf: url, encoding: .utf8)
            vaultText = fileContent
        } catch {
            errorMsg = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func restoreVault(hexVaultData: String, modelContext: ModelContext) -> Bool {
        let vaultData = Data(hexString: hexVaultData)
        guard let vaultData else {
            errorMsg = "invalid vault data"
            return false
        }
        let decoder = JSONDecoder()
        do {
            let vault = try decoder.decode(Vault.self,
                                           from: vaultData)
            modelContext.insert(vault)
            return true
        } catch {
            logger.error("fail to restore vault: \(error.localizedDescription)")
            errorMsg = "fail to restore vault: \(error.localizedDescription)"
        }
        return false
    }
}

#Preview {
    ImportWalletView(presentationStack: .constant([]))
}
