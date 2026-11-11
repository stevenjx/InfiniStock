import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Spotlight 索引。用序列号做唯一标识，改价、出库、撤销都会刷新同一条记录。
enum SpotlightIndexer {
    static let domain = "com.infinistock.items"

    static func index(_ item: Item) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = item.modelName
        attributes.contentDescription = [
            item.serialNumber,
            item.specSummary,
            item.status.label,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        attributes.keywords = [item.serialNumber, item.modelName]

        let searchable = CSSearchableItem(
            uniqueIdentifier: item.serialNumber,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([searchable], completionHandler: nil)
    }

    static func remove(serial: String) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [serial], completionHandler: nil)
    }
}
