//
//  WithError.swift
//  VultisigApp
//
//  Created by Claude on 2026-01-26.
//

import SwiftUI

struct PresentableError: Error, Identifiable, Equatable {
    let id = UUID()
    let title: String
    let description: String

    static func == (lhs: PresentableError, rhs: PresentableError) -> Bool {
        lhs.title == rhs.title && lhs.description == rhs.description
    }

    init(title: String, description: String) {
        self.title = title
        self.description = description
    }

    init(from error: Error) {
        if let customError = error as? ErrorWithCustomPresentation {
            self.title = customError.errorTitle
            self.description = customError.errorDescription
        } else {
            self.title = NSLocalizedString("error", comment: "")
            self.description = error.localizedDescription
        }
    }
}

private struct WithErrorModifier: ViewModifier {
    @Binding var error: Error?
    let errorType: ErrorView.ErrorType
    let buttonTitle: String
    let onRetry: () -> Void

    @State private var presentableError: PresentableError?

    func body(content: Content) -> some View {
        content
            .onLoad {
                updatePresentableError()
            }
            .onChange(of: error == nil) { _, _ in
                updatePresentableError()
            }
            .onChange(of: presentableError) { _, presentable in
                if presentable == nil {
                    error = nil
                }
            }
            #if os(iOS)
            .fullScreenCover(item: $presentableError) { presentable in
                ErrorScreen(
                    type: errorType,
                    title: presentable.title,
                    description: presentable.description,
                    buttonTitle: buttonTitle
                ) {
                    presentableError = nil
                    error = nil
                    onRetry()
                }
            }
        #else
            .crossPlatformSheet(item: $presentableError) { presentable in
                ErrorScreen(
                    type: errorType,
                    title: presentable.title,
                    description: presentable.description,
                    buttonTitle: buttonTitle
                ) {
                    presentableError = nil
                    error = nil
                    onRetry()
                }
                .sheetStyle()
                .applySheetSize()
            }
        #endif
    }

    private func updatePresentableError() {
        if let error {
            presentableError = PresentableError(from: error)
        } else {
            presentableError = nil
        }
    }
}

extension View {
    /// Presents a fullscreen error screen when an error occurs
    /// - Parameters:
    ///   - error: Binding to an optional error
    ///   - errorType: Type of error presentation (alert or warning)
    ///   - buttonTitle: Title for the retry button
    ///   - onRetry: Action to perform when retry button is tapped
    func withError(
        error: Binding<Error?>,
        errorType: ErrorView.ErrorType = .alert,
        buttonTitle: String = NSLocalizedString("tryAgain", comment: ""),
        onRetry: @escaping () -> Void
    ) -> some View {
        modifier(WithErrorModifier(
            error: error,
            errorType: errorType,
            buttonTitle: buttonTitle,
            onRetry: onRetry
        ))
    }
}
