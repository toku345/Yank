import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
final class ClipItem {
    var title: String
    var primaryType: String
    var availableTypes: [String]
    var stringValue: String?
    var rtfData: Data?
    var rtfdData: Data?
    var htmlData: Data?
    var pdfData: Data?
    // NSPasteboard normalizes images to TIFF; PNG is converted at capture time
    var imageData: Data?
    var fileURLs: [String]?
    var createdAt: Date

    var primaryUTType: UTType? { UTType(primaryType) }

    init(
        title: String,
        primaryType: String,
        availableTypes: [String],
        stringValue: String? = nil,
        rtfData: Data? = nil,
        rtfdData: Data? = nil,
        htmlData: Data? = nil,
        pdfData: Data? = nil,
        imageData: Data? = nil,
        fileURLs: [String]? = nil,
        createdAt: Date = Date()
    ) {
        self.title = title
        self.primaryType = primaryType
        self.availableTypes = availableTypes
        self.stringValue = stringValue
        self.rtfData = rtfData
        self.rtfdData = rtfdData
        self.htmlData = htmlData
        self.pdfData = pdfData
        self.imageData = imageData
        self.fileURLs = fileURLs
        self.createdAt = createdAt
    }
}
