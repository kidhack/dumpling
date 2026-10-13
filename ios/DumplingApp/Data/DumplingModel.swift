import CoreData

/// The Core Data model, defined in code. It mirrors the schema SwiftData created, so the existing
/// store (and its iCloud records) open without migration.
enum DumplingModel {
    static let shared: NSManagedObjectModel = make()

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true,
                                  default value: Any? = nil) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        a.defaultValue = value
        return a
    }

    private static func make() -> NSManagedObjectModel {
        let item = NSEntityDescription()
        item.name = "Item"
        item.managedObjectClassName = "DumplingItem"

        let list = NSEntityDescription()
        list.name = "ItemList"
        list.managedObjectClassName = "DumplingList"

        let rule = NSEntityDescription()
        rule.name = "RoutingRule"

        let itemList = NSRelationshipDescription()
        itemList.name = "list"
        itemList.destinationEntity = list
        itemList.minCount = 0
        itemList.maxCount = 1
        itemList.isOptional = true
        itemList.deleteRule = .nullifyDeleteRule

        let listItems = NSRelationshipDescription()
        listItems.name = "items"
        listItems.destinationEntity = item
        listItems.minCount = 0
        listItems.maxCount = 0
        listItems.isOptional = true
        listItems.deleteRule = .nullifyDeleteRule

        itemList.inverseRelationship = listItems
        listItems.inverseRelationship = itemList

        item.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("timestamp", .dateAttributeType, optional: false),
            attribute("contentURL", .stringAttributeType),
            attribute("contentText", .stringAttributeType),
            attribute("sourceApp", .stringAttributeType),
            attribute("userNote", .stringAttributeType),
            attribute("quickTag", .stringAttributeType),
            attribute("status", .stringAttributeType, optional: false, default: "pending"),
            attribute("syncedAt", .dateAttributeType),
            attribute("category", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("relevantDate", .dateAttributeType),
            attribute("filedTo", .stringAttributeType),
            attribute("eventKitID", .stringAttributeType),
            attribute("sortError", .stringAttributeType),
            attribute("location", .stringAttributeType),
            attribute("latitude", .doubleAttributeType),
            attribute("longitude", .doubleAttributeType),
            attribute("isAllDay", .booleanAttributeType, optional: false, default: false),
            attribute("archivedAt", .dateAttributeType),
            attribute("isHearted", .booleanAttributeType, optional: false, default: false),
            attribute("otherHearts", .integer64AttributeType, optional: false, default: 0),
            itemList,
        ]

        list.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("name", .stringAttributeType, optional: false, default: ""),
            attribute("createdAt", .dateAttributeType, optional: false),
            listItems,
        ]

        rule.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("pattern", .stringAttributeType, optional: false, default: ""),
            attribute("patternType", .stringAttributeType, optional: false, default: "substring"),
            attribute("contentType", .stringAttributeType, optional: false, default: ""),
            attribute("action", .stringAttributeType, optional: false, default: ""),
            attribute("target", .stringAttributeType, optional: false, default: ""),
            attribute("isEnabled", .booleanAttributeType, optional: false, default: true),
            attribute("matchCount", .integer64AttributeType, optional: false, default: 0),
            attribute("createdAt", .dateAttributeType, optional: false),
        ]

        let model = NSManagedObjectModel()
        model.entities = [item, list, rule]
        return model
    }
}
