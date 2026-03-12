import Foundation

struct APIFieldErrorResponse: Decodable {
    let ok: Bool?
    let error: APIErrorBody
}

struct APIErrorBody: Decodable {
    let code: String
    let message: String
    let fieldErrors: [String: String]?
    let retryAfterSec: Int?
}

struct AuthSession: Codable {
    let email: String
    let userId: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt.addingTimeInterval(-30)
    }
}

struct WishlistPreview: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let occasionDate: String?
    let occasionNote: String?
    let currency: String
    let updatedAt: String
    let shareUrlPreview: String
    let reservedCount: Int
}

struct WishlistListResponse: Decodable {
    let ok: Bool
    let wishlists: [WishlistPreview]
}

struct WishlistCreatePayload: Encodable {
    let title: String
    let occasionDate: String?
    let occasionNote: String?
    let currency: String
}

struct WishlistCreateResponse: Decodable {
    let ok: Bool
    let wishlist: WishlistCreatedModel
}

struct WishlistCreatedModel: Decodable {
    let id: String
    let title: String
    let occasionDate: String?
    let occasionNote: String?
    let currency: String
    let updatedAt: String
    let shareUrl: String
    let shareUrlPreview: String
}

struct WishlistUpdatePayload: Encodable {
    let title: String
    let occasionDate: String?
    let occasionNote: String?
}

struct WishlistUpdateResponse: Decodable {
    let ok: Bool
    let wishlist: WishlistPreview
}

struct WishlistDeleteResponse: Decodable {
    let ok: Bool
    let deletedWishlistId: String
}

struct ItemRecord: Codable, Identifiable, Hashable {
    let id: String
    let wishlistId: String
    let ownerEmail: String
    let title: String
    let description: String?
    let url: String?
    let priceCents: Int?
    let imageUrl: String?
    let imageUrls: [String]
    let isGroupFunded: Bool
    let targetCents: Int?
    let fundingDeadlineAt: String?
    let shortfallPolicy: String
    let fundedCents: Int
    let contributorCount: Int
    let archivedAt: String?
    let createdAt: String
    let updatedAt: String

    var normalizedImageURLs: [String] {
        if !imageUrls.isEmpty {
            return imageUrls.filter { !$0.isEmpty }
        }
        if let imageUrl, !imageUrl.isEmpty {
            return [imageUrl]
        }
        return []
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}

struct ItemsListResponse: Decodable {
    let ok: Bool
    let items: [ItemRecord]
}

struct ItemPayload: Encodable {
    let wishlistId: String?
    let title: String
    let description: String?
    let url: String?
    let priceCents: Int?
    let imageUrls: [String]
    let isGroupFunded: Bool
    let targetCents: Int?
}

struct ItemMutationResponse: Decodable {
    let ok: Bool
    let item: ItemRecord
    let warning: String?
}

struct ItemArchiveResponse: Decodable {
    let ok: Bool
    let item: ItemRecord
}

struct ImagePrepareRequest: Encodable {
    let mode: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
}

struct ImagePreviewRequest: Encodable {
    let mode: String
    let imageIndex: Int
}

struct ImagePrepareResponse: Decodable {
    let ok: Bool
    let uploadUrl: String
    let expiresInSec: Int?
    let maxUploadMb: Int?
    let allowedMimeTypes: [String]?
}

struct ImageUploadResponse: Decodable {
    let ok: Bool
    let item: ItemRecord
    let previewUrl: String?
    let expiresInSec: Int?
}

struct ImagePreviewResponse: Decodable {
    let ok: Bool
    let previewUrl: String?
    let expiresInSec: Int?
}

struct DraftParseRequest: Encodable {
    let draftText: String
}

struct ParsedDraft: Decodable {
    let title: String?
    let description: String?
    let priceCents: Int?
}

struct DraftParseResponse: Decodable {
    let ok: Bool
    let parsed: ParsedDraft
    let priceNeedsReview: Bool
    let priceReviewMessage: String?
    let priceConfidence: Double?
}

struct MetadataRequest: Encodable {
    let url: String
    let specNotes: String?
}

struct ImportedMetadata: Decodable {
    let title: String?
    let description: String?
    let imageUrl: String?
    let imageUrls: [String]?
    let priceCents: Int?
    let priceNeedsReview: Bool?
    let priceReviewMessage: String?
    let priceConfidence: Double?
}

struct MetadataResponse: Decodable {
    let ok: Bool
    let metadata: ImportedMetadata
}

struct ShortfallRequest: Encodable {
    let action: String
}

struct ShortfallResponse: Decodable {
    let ok: Bool
    let item: ItemRecord
    let appliedAction: String
}

struct PublicWishlistModel: Codable, Hashable {
    let id: String
    let title: String
    let occasionDate: String?
    let occasionNote: String?
    let currency: String
    let shareUrl: String
    let itemCount: Int
}

struct PublicContributorEntry: Codable, Hashable, Identifiable {
    let guestEmail: String
    let amountCents: Int
    let contributionCount: Int

    var id: String {
        guestEmail
    }
}

struct PublicItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let url: String?
    let imageUrl: String?
    let imageUrls: [String]?
    let priceCents: Int?
    let isGroupFunded: Bool
    let targetCents: Int?
    let fundedCents: Int
    let contributorCount: Int
    let contributorBreakdown: [PublicContributorEntry]?
    let progressRatio: Double
    let availability: String

    var normalizedImageURLs: [String] {
        if let imageUrls, !imageUrls.isEmpty {
            let filtered = imageUrls.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !filtered.isEmpty {
                return filtered
            }
        }
        if let imageUrl, !imageUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [imageUrl]
        }
        return []
    }

    var normalizedContributorBreakdown: [PublicContributorEntry] {
        guard let contributorBreakdown else { return [] }
        return contributorBreakdown.filter { !$0.guestEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct PublicWishlistResponse: Decodable {
    let ok: Bool
    let version: String
    let wishlist: PublicWishlistModel
    var items: [PublicItem]
}

struct SharedItemWishlistSummary: Decodable {
    let id: String
    let title: String
    let occasionDate: String?
    let occasionNote: String?
    let currency: String
}

struct PublicSharedItemResponse: Decodable {
    let ok: Bool
    let canReserve: Bool
    let message: String?
    let wishlist: SharedItemWishlistSummary
    let item: PublicItem
}

struct PublicItemShareLinkResponse: Decodable {
    let ok: Bool
    let itemToken: String
    let shareUrl: String
}

struct ReservationRequest: Encodable {
    let itemId: String
    let action: String
}

struct ReservationResponse: Decodable {
    let ok: Bool
    let reservation: ReservationStatusModel
    let item: PublicItem
}

struct ReservationStatusModel: Decodable {
    let status: String
}

struct ContributionRequest: Encodable {
    let itemId: String
    let amountCents: Int
}

struct ContributionResponse: Decodable {
    let ok: Bool
    let contribution: ContributionModel
    let item: PublicItem
}

struct ContributionModel: Decodable {
    let id: String
    let amountCents: Int
    let createdAt: String
}

struct ArchiveAlertResponse: Decodable {
    let ok: Bool
    let alert: ArchiveAlert?
}

struct ArchiveAlert: Decodable, Identifiable, Hashable {
    let id: String
    let archivedItemTitle: String
    let archivedItemPriceCents: Int?
    let suggestedItemIds: [String]
    let createdAt: String
}

struct ArchiveAlertDismissRequest: Encodable {
    let notificationId: String
}

struct SimpleOKResponse: Decodable {
    let ok: Bool
}

struct MyReservationsResponse: Decodable {
    let ok: Bool
    let itemIds: [String]
}

struct ActivityEntry: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let action: String
    let wishlistId: String
    let wishlistTitle: String
    let itemId: String?
    let itemTitle: String?
    let amountCents: Int?
    let status: String?
    let openCount: Int?
    let happenedAt: String
    let wishlistUnavailable: Bool?
    let openItemPath: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case action
        case wishlistId
        case wishlistTitle
        case itemId
        case itemTitle
        case amountCents
        case status
        case openCount
        case happenedAt
        case wishlistUnavailable
        case openItemPath

        case wishlist_id
        case wishlist_title
        case item_id
        case item_title
        case amount_cents
        case open_count
        case happened_at
        case wishlist_unavailable
        case open_item_path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        action = try container.decode(String.self, forKey: .action)
        wishlistId = try container.decodeIfPresent(String.self, forKey: .wishlistId)
            ?? container.decode(String.self, forKey: .wishlist_id)
        wishlistTitle = try container.decodeIfPresent(String.self, forKey: .wishlistTitle)
            ?? container.decode(String.self, forKey: .wishlist_title)
        itemId = try container.decodeIfPresent(String.self, forKey: .itemId)
            ?? container.decodeIfPresent(String.self, forKey: .item_id)
        itemTitle = try container.decodeIfPresent(String.self, forKey: .itemTitle)
            ?? container.decodeIfPresent(String.self, forKey: .item_title)
        amountCents = try container.decodeIfPresent(Int.self, forKey: .amountCents)
            ?? container.decodeIfPresent(Int.self, forKey: .amount_cents)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        openCount = try container.decodeIfPresent(Int.self, forKey: .openCount)
            ?? container.decodeIfPresent(Int.self, forKey: .open_count)
        happenedAt = try container.decodeIfPresent(String.self, forKey: .happenedAt)
            ?? container.decode(String.self, forKey: .happened_at)
        wishlistUnavailable = try container.decodeIfPresent(Bool.self, forKey: .wishlistUnavailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .wishlist_unavailable)
        openItemPath = try container.decodeIfPresent(String.self, forKey: .openItemPath)
            ?? container.decodeIfPresent(String.self, forKey: .open_item_path)
    }
}

struct ActivityResponse: Decodable {
    let ok: Bool
    let activities: [ActivityEntry]
}

struct ActivityDeleteWishlistRequest: Encodable {
    let wishlistId: String
}

struct ActivityDeleteWishlistResponse: Decodable {
    let ok: Bool
    let wishlistId: String
    let releasedReservationCount: Int
    let removedWishlistOpenCount: Int
}

struct PendingImage: Identifiable, Hashable {
    let id: UUID
    let data: Data
    let filename: String
    let mimeType: String

    init(data: Data, filename: String = "image.jpg", mimeType: String = "image/jpeg") {
        self.id = UUID()
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }
}
