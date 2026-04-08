import Foundation

enum EditorDialogState: String, Identifiable {
    case charShape
    case paraShape
    case tableProperties
    case mergeCells
    case bookmarks
    case fields

    var id: String { rawValue }
}
