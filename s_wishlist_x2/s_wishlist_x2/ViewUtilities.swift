import Foundation

private func parseISO8601Date(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = formatter.date(from: raw) {
        return parsed
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
}

func formatMoney(cents: Int?, currency: String = "USD") -> String {
    guard let cents = cents else { return "Not set" }

    let amount = Double(cents) / 100.0
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2

    if let formatted = formatter.string(from: NSNumber(value: amount)) {
        return formatted
    }

    return String(format: "$%.2f", amount)
}

func parseMoneyToCents(_ raw: String) -> Int? {
    let trimmed = raw.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
    return Int((value * 100).rounded())
}

func formatDateLabel(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "No date set" }

    if let date = parseISO8601Date(raw) {
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    let fallback = DateFormatter()
    fallback.dateFormat = "yyyy-MM-dd"
    if let date = fallback.date(from: raw) {
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    return raw
}

func formatTimestamp(_ raw: String) -> String {
    if let date = parseISO8601Date(raw) {
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
    return raw
}

func formatEventDate(_ raw: String) -> String {
    let display = DateFormatter()
    display.locale = Locale(identifier: "en_US_POSIX")
    display.timeZone = TimeZone(secondsFromGMT: 0)
    display.dateFormat = "MMM d, yyyy"

    if let date = parseISO8601Date(raw) {
        return display.string(from: date)
    }

    let fallback = DateFormatter()
    fallback.dateFormat = "yyyy-MM-dd"
    if let date = fallback.date(from: raw) {
        return display.string(from: date)
    }

    return raw
}

func randomIdempotencyKey() -> String {
    UUID().uuidString.lowercased()
}

func extractShareToken(from preview: String?) -> String? {
    guard let preview = preview else { return nil }
    return AppConfig.shareToken(from: preview)
}

enum SharedWishlistTokenCache {
    private static let storageKey = "s_wishlist_x2.shared_wishlist_tokens"
    private static let maxEntries = 200

    static func save(token: String, forWishlistId wishlistId: String) {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWishlistId = wishlistId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedToken.isEmpty, !normalizedWishlistId.isEmpty else {
            return
        }

        var map = loadMap()
        map[normalizedWishlistId] = normalizedToken

        if map.count > maxEntries {
            // Deterministic pruning to keep storage bounded.
            let overflow = map.count - maxEntries
            let staleKeys = map.keys.sorted().prefix(overflow)
            for key in staleKeys {
                map.removeValue(forKey: key)
            }
        }

        persistMap(map)
    }

    static func token(forWishlistId wishlistId: String) -> String? {
        let normalizedWishlistId = wishlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWishlistId.isEmpty else { return nil }

        return loadMap()[normalizedWishlistId]
    }

    private static func loadMap() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func persistMap(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

func mergeDraftText(currentDraftText: String, importedTitle: String?, importedDescription: String?, importedPriceCents: Int?) -> String {
    var importedLines: [String] = []

    if let importedTitle, !importedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        importedLines.append("Title: \(importedTitle.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    if let importedPriceCents = importedPriceCents {
        importedLines.append("Price: \(formatMoney(cents: importedPriceCents))")
    }

    if let importedDescription, !importedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        importedLines.append("Description:")
        importedLines.append(importedDescription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    let importedText = importedLines.joined(separator: "\n")
    let current = currentDraftText.trimmingCharacters(in: .whitespacesAndNewlines)

    if current.isEmpty {
        return importedText
    }

    if importedText.isEmpty {
        return current
    }

    return "\(current)\n\nImported from URL:\n\(importedText)"
}

func buildDraftText(from item: ItemRecord) -> String {
    var lines: [String] = []
    if !item.title.isEmpty {
        lines.append("Title: \(item.title)")
    }
    if let priceCents = item.priceCents {
        lines.append("Price: \(formatMoney(cents: priceCents))")
    }
    if let description = item.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("Description:")
        lines.append(description.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return lines.joined(separator: "\n")
}

func dedupedStrings(_ input: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []

    for value in input {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if seen.contains(trimmed) { continue }
        seen.insert(trimmed)
        output.append(trimmed)
    }

    return output
}
