import Foundation

enum AppConfig {
    // Update these if backend host or Supabase project changes.
    static let apiBaseURLString = "https://w-wishlist-x2.vercel.app"
    static let supabaseURLString = "https://iwcntrhixhbwzvxngunl.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3Y250cmhpeGhid3p2eG5ndW5sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0NDE4MTMsImV4cCI6MjA4NzAxNzgxM30.A5USHOIZ7TlQKxuwjJClNkX9oN6Uhe-wNK-l1hk6ipM"

    static var apiBaseURL: URL {
        guard let url = URL(string: apiBaseURLString) else {
            fatalError("Invalid apiBaseURLString")
        }
        return url
    }

    static var supabaseURL: URL {
        guard let url = URL(string: supabaseURLString) else {
            fatalError("Invalid supabaseURLString")
        }
        return url
    }

    static func shareToken(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let routedToken = routedToken(from: trimmed, routeSegment: "l") {
            return routedToken
        }

        if trimmed.contains("/") || trimmed.contains(":") {
            guard let url = URL(string: trimmed) else { return nil }
            let pieces = url.pathComponents.filter { $0 != "/" }
            return pieces.last?.removingPercentEncoding
        }

        if trimmed.contains("?") {
            let parts = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true)
            return String(parts[0])
        }

        return trimmed
    }

    static func itemShareToken(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return routedToken(from: trimmed, routeSegment: "i")
    }

    private static func routedToken(from input: String, routeSegment: String) -> String? {
        guard let url = URL(string: input) else { return nil }
        let pieces = url.pathComponents.filter { $0 != "/" }
        if let idx = pieces.firstIndex(of: routeSegment), pieces.indices.contains(idx + 1) {
            return pieces[idx + 1].removingPercentEncoding
        }
        return nil
    }
}
