import Foundation

enum EditorDialogState: String, Identifiable {
    case pageSetup
    case charShape
    case paraShape
    case tableProperties
    case mergeCells
    case bookmarks
    case fields
    case headerSetup
    case footerSetup

    var id: String { rawValue }
}
