import Foundation
import GRDB

extension Mutation {
    /// Sets or clears one of a project's own fields other than Status, Priority and the due date: an iteration,
    /// a date, or an option of a field like "Workstream".
    public struct SetProjectField: Codable, Sendable, Equatable {
        public var itemId: String
        public var projectId: String
        public var fieldId: String
        /// The field's name, for the list of queued changes.
        public var fieldName: String
        /// The new value; nil clears the field.
        public var value: FieldValue?
        /// What the value is called, such as the iteration's title, for the list of queued changes.
        public var valueName: String?
        /// The value before the first of the still-unsent changes to it.
        public var base: FieldValue?

        func apply(_ db: Database) throws {
            guard var item = try Item.fetchOne(db, key: itemId) else { return }
            if let value, !value.isEmpty {
                item.fieldValues[fieldId] = value
            } else {
                item.fieldValues[fieldId] = nil
            }
            item.dirty = true
            try item.update(db)
        }
    }
}

extension Item {
    /// Fills in the project's own fields a new issue starts with.
    mutating func apply(_ values: [String: FieldValue]?) {
        for (fieldId, value) in values ?? [:] where !value.isEmpty {
            fieldValues[fieldId] = value
        }
    }
}
