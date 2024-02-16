import SwiftUI

struct NavigationButtons {
    // Define a static function or computed property for the question mark button
    static var questionMarkButton: some View {
        Button(action: {
            // Define the action for your question mark button here
            print("Question mark button tapped")
        }) {
            Image(systemName: "questionmark.circle")
        }
    }

    // Adjust the backButton to accept the presentationStack as a parameter
    static func backButton(presentationStack: Binding<[CurrentScreen]>) -> some View {
        Button(action: {
            if !presentationStack.wrappedValue.isEmpty {
                presentationStack.wrappedValue.removeLast()
            }
        }) {
            Image(systemName: "chevron.left")
        }
    }
    
    static func refreshButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise.circle")
        }
    }
    
    static func qrCodeButton(presentationStack: Binding<[CurrentScreen]>) -> some View {
        Button(action: {
            presentationStack.wrappedValue.append(.joinKeygen)
        }) {
            Image(systemName: "qrcode.viewfinder")
        }
    }
}

// Modifier to conditionally apply .navigationBarTitleDisplayMode for non-macOS targets
struct InlineNavigationBarTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline)
    }
}
