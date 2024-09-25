import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct AddressTextField: View {
    @Binding var contractAddress: String
    var validateAddress: (String) -> Void
    
    @State var showScanner = false
    @State var showImagePicker = false
    
    @State var showScanIcon = true
    @State var showAddressBookIcon = true
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        content
    }
    
    var placeholder: some View {
        Text(NSLocalizedString("enterContractAddress", comment: "").toFormattedTitleCase())
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            Image(systemName: "camera")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var fileButton: some View {
        Button {
            showImagePicker.toggle()
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var addressBookButton: some View {
        NavigationLink {
            AddressBookView(returnAddress: $contractAddress)
        } label: {
            Image(systemName: "text.book.closed")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
}
