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
        self.sheet(isPresented: isPresented) {
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

fileprivate struct ShareSheetViewController: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    var completion: ((Bool) -> Void)?
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareSheetViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            isPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completion?(completed)
            }
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ShareSheetViewController>) {}
}
#endif
