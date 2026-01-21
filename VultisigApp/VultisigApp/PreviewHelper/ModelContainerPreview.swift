/*
 See the LICENSE.txt file for this sample’s licensing information.
 
 Abstract:
 A view to use only in previews that creates a model container before
 showing the preview content.
 */

import SwiftUI
import SwiftData

struct ModelContainerPreview<Content: View>: View {
    var content: () -> Content
    let container: ModelContainer

    /// Creates an instance of the model container preview.
    ///
    /// This view creates the model container before displaying the preview
    /// content. The view is intended for use in previews only.
    ///
    ///     #Preview {
    ///         ModelContainerPreview {
    ///             AnimalEditor(animal: nil)
    ///                 .environment(NavigationContext())
    ///             } modelContainer: {
    ///                 let schema = Schema([AnimalCategory.self, Animal.self])
    ///                 let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    ///                 let container = try ModelContainer(for: schema, configurations: [configuration])
    ///                 Task { @MainActor in
    ///                     AnimalCategory.insertSampleData(modelContext: container.mainContext)
    ///                 }
    ///             return container
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - content: A view that describes the content to preview.
    ///   - modelContainer: A closure that returns a model container.
    init(@ViewBuilder content: @escaping () -> Content, modelContainer: @escaping () throws -> ModelContainer) {
        self.content = content
        do {
            self.container = try MainActor.assumeIsolated(modelContainer)
        } catch {
            fatalError("Failed to create the model container: \(error.localizedDescription)")
        }
    }

    /// Creates a view that creates the provided model container before displaying
    /// the preview content.
    ///
    /// This view creates the model container before displaying the preview
    /// content. The view is intended for use in previews only.
    ///
    ///     #Preview {
    ///         ModelContainerPreview(SampleModelContainer.main) {
    ///             AnimalEditor(animal: .kangaroo)
    ///                 .environment(NavigationContext())
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - modelContainer: A closure that returns a model container.
    ///   - content: A view that describes the content to preview.
    init(_ modelContainer: @escaping () throws -> ModelContainer, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, modelContainer: modelContainer)
    }

    var body: some View {
        content()
            .modelContainer(container)
    }
}
