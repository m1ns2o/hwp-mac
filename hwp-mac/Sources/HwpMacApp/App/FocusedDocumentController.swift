import SwiftUI

private struct ActiveDocumentControllerKey: FocusedValueKey {
    typealias Value = DocumentController
}

extension FocusedValues {
    var activeDocumentController: DocumentController? {
        get { self[ActiveDocumentControllerKey.self] }
        set { self[ActiveDocumentControllerKey.self] = newValue }
    }
}
