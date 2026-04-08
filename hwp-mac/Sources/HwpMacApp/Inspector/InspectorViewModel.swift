import Combine
import Foundation

@MainActor
final class InspectorViewModel: ObservableObject {
    @Published var zoomPercentage: Int = 100
    @Published var pageLabel: String = "0 / 0"
    @Published var fileLabel: String = "Untitled"

    func sync(from documentController: DocumentController) {
        zoomPercentage = Int(documentController.viewportController.zoom * 100)
        let totalPages = documentController.pageInfos.count
        let currentPage = totalPages == 0 ? 0 : documentController.selectedPageIndex + 1
        pageLabel = "\(currentPage) / \(totalPages)"
        fileLabel = documentController.displayName
    }
}
