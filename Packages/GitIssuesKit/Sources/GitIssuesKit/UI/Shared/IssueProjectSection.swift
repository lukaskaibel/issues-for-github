import Foundation

/// An issue has a separate project item, and separate field values, on each board it belongs to.
struct IssueProjectSection: Identifiable {
    var project: Project
    var item: Item
    var fields: [ProjectField]

    // Sync replaces a newly added card's local ID; keep the section's identity through that remap.
    var id: String { "\(project.id):\(item.contentId ?? item.id)" }

    static func sections(for item: Item, items: [Item], projects: [Project], fields: [ProjectField]) -> [Self] {
        var members = items.filter { candidate in
            candidate.isOnBoard && (candidate.id == item.id || item.contentId != nil && candidate.contentId == item.contentId)
        }
        // Inbox and newly created items may not have reached the observed list yet.
        if item.isOnBoard, !members.contains(where: { $0.id == item.id }) { members.append(item) }
        var result: [Self] = projects.compactMap { project in
            guard !project.closed else { return nil }
            guard let member = members.first(where: { $0.projectId == project.id }) else { return nil }
            return Self(project: project, item: member, fields: fields.filter {
                $0.projectId == project.id && $0.kind.isProjectValue
            }.sorted { $0.position < $1.position })
        }
        // The board the issue was opened from stays first, so its version and dates are immediately within reach.
        if let index = result.firstIndex(where: { $0.project.id == item.projectId }), index > 0 {
            result.insert(result.remove(at: index), at: 0)
        }
        return result
    }

    func value(of field: ProjectField) -> FieldValue? {
        if field.id == project.statusFieldId { return item.statusId.map { FieldValue(optionId: $0) } }
        if field.id == project.priorityFieldId { return item.priorityId.map { FieldValue(optionId: $0) } }
        if field.id == project.dueFieldId { return item.dueDate.map { FieldValue(date: $0) } }
        return item.fieldValues[field.id]
    }
}

/// Text and numeric fields share an editor, but invalid numbers must never clear an existing value.
enum ProjectFieldInput {
    static func number(_ text: String, locale: Locale = .current) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let decimal = NSRegularExpression.escapedPattern(for: formatter.decimalSeparator ?? ".")
        let grouping = NSRegularExpression.escapedPattern(for: formatter.groupingSeparator ?? ",")
        let digits = "\\p{Nd}+"
        let integer = "\(digits)(?:\(grouping)\(digits))*"
        let signs = Set(["+", "-", formatter.plusSign ?? "+", formatter.minusSign ?? "-"])
            .sorted().map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let sign = "(?:\(signs))?"
        // Foundation's numeric parser accepts a valid prefix, even in strict mode ("12abc" becomes 12).
        let pattern = "^\(sign)(?:\(integer)(?:\(decimal)\\p{Nd}*)?|\(decimal)\(digits))(?:[eE]\(sign)\(digits))?$"
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.locale(locale)
        guard let value = try? Double(text, format: format, lenient: false), value.isFinite else { return nil }
        return value
    }
}
