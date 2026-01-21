//
//  ShareSheetViewController.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-07.
//
#if os(iOS)
import SwiftUI

extension View {
    func shareSheet(isPresented: Binding<Bool>, activityItems: [Any], completion: ((Bool) -> Void)?, applicationActivities: [UIActivity]? = nil) -> some View {
        self.crossPlatformSheet(isPresented: isPresented) {
            ShareSheetViewController(
                isPresented: isPresented,
                activityItems: activityItems,
                applicationActivities: applicationActivities,
                completion: completion
            )
            .presentationDetents([.medium])
            .ignoresSafeArea(.all)

        }
    }
}

private struct ShareSheetViewController: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var activityItems: [Any]
    var applicationActivities: [UIActivity]?
    var completion: ((Bool) -> Void)?

    class Coordinator: NSObject {
        // Weak reference to prevent retain cycles
        var activityViewController: UIActivityViewController?
        var completion: ((Bool) -> Void)?
        var hasCompleted: Bool = false

        init(completion: ((Bool) -> Void)? = nil) {
            self.completion = completion
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: self.completion)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareSheetViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        context.coordinator.activityViewController = controller

        // Configure the controller
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks,
            .markupAsPDF
        ]

        controller.completionWithItemsHandler = { _, completed, _, error in
            // Prevent multiple completion calls
            guard !context.coordinator.hasCompleted  else { return }
            context.coordinator.hasCompleted = true

            if let error = error {
                print("Error sharing: \(error.localizedDescription)")
            }

            // Dismiss the sheet first
            DispatchQueue.main.async {
                self.isPresented = false
            }

            // Use a longer delay to ensure navigation state is completely stable
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                context.coordinator.completion?(completed)
                context.coordinator.activityViewController = nil
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ShareSheetViewController>) {
        // No updates needed
    }
}
#endif
