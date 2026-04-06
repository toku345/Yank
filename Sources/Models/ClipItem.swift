import Foundation
import SwiftData

@Model
final class ClipItem {
    var title: String
    var primaryType: String
    var availableTypes: [String]
    var stringValue: String?
    var rtfData: Data?
    var rtfdData: Data?
    var pdfData: Data?
    var pngData: Data?
    var tiffData: Data?
    var fileURLs: [String]?
    var urlStrings: [String]?
    var createdAt: Date
    var isPinned: Bool
    var isSensitive: Bool

    init(
        title: String,
        primaryType: String,
        availableTypes: [String],
        stringValue: String? = nil,
        rtfData: Data? = nil,
        rtfdData: Data? = nil,
        pdfData: Data? = nil,
        pngData: Data? = nil,
        tiffData: Data? = nil,
        fileURLs: [String]? = nil,
        urlStrings: [String]? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        isSensitive: Bool = false
    ) {
        self.title = title
        self.primaryType = primaryType
        self.availableTypes = availableTypes
        self.stringValue = stringValue
        self.rtfData = rtfData
        self.rtfdData = rtfdData
        self.pdfData = pdfData
        self.pngData = pngData
        self.tiffData = tiffData
        self.fileURLs = fileURLs
        self.urlStrings = urlStrings
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isSensitive = isSensitive
    }
}
