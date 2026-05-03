import Foundation

struct UserDTO: Codable, Identifiable {
    let id: String
    let fullName: String
    let city: String
    let email: String
    let bio: String
    let role: String
    let blockState: String
    let createdAt: Date
    let updatedAt: Date
}

struct CommentDTO: Codable, Identifiable {
    let id: String
    let authorName: String
    let body: String
    let createdAt: Date
    let updatedAt: Date
}

struct NewsPostDTO: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let imageURL: String?
    let body: String
    let authorName: String
    let publishedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let comments: [CommentDTO]
    let moderationStatus: String
    let likeCount: Int
    let likeState: String
}

struct EventDTO: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let details: String
    let city: String
    let venue: String
    let imageURL: String?
    let startDate: Date
    let endDate: Date
    let createdAt: Date
    let updatedAt: Date
    let capacity: Int?
    let registeredCount: Int
    let comments: [CommentDTO]
    let moderationStatus: String
    let registrationState: String
    let likeCount: Int
    let likeState: String
}

struct OrganizationDTO: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let city: String
    let imageURL: String?
    let contactEmail: String?
    let website: String?
    let createdAt: Date
    let moderationStatus: String
    let likeCount: Int
    let likeState: String
}

struct MarketplaceItemDTO: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let city: String
    let price: Decimal?
    let isFreeGift: Bool
    let expirationDate: Date
    let sellerName: String
    let createdAt: Date
    let updatedAt: Date
    let contactValue: String
    let contactMethod: String
    let comments: [CommentDTO]
    let moderationStatus: String
    let likeCount: Int
    let likeState: String
}

extension AppUser {
    init(dto: UserDTO) {
        self.init(
            id: dto.id,
            fullName: dto.fullName,
            city: dto.city,
            email: dto.email,
            bio: dto.bio,
            role: UserRole(rawValue: dto.role) ?? .user,
            blockState: UserBlockState(rawValue: dto.blockState) ?? .active,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    var dto: UserDTO {
        UserDTO(
            id: id,
            fullName: fullName,
            city: city,
            email: email,
            bio: bio,
            role: role.rawValue,
            blockState: blockState.rawValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension Comment {
    init(dto: CommentDTO) {
        self.init(
            id: dto.id,
            authorName: dto.authorName,
            body: dto.body,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    var dto: CommentDTO {
        CommentDTO(
            id: id,
            authorName: authorName,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension NewsPost {
    init(dto: NewsPostDTO) {
        self.init(
            id: dto.id,
            title: dto.title,
            subtitle: dto.subtitle,
            imageURL: dto.imageURL,
            body: dto.body,
            authorName: dto.authorName,
            publishedAt: dto.publishedAt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            comments: dto.comments.map {
                Comment(
                    id: $0.id,
                    authorName: $0.authorName,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            moderationStatus: ModerationStatus(rawValue: dto.moderationStatus) ?? .draft,
            likeCount: dto.likeCount,
            likeState: LikeState(rawValue: dto.likeState) ?? .notLiked
        )
    }

    var dto: NewsPostDTO {
        NewsPostDTO(
            id: id,
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            body: body,
            authorName: authorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            comments: comments.map(\.dto),
            moderationStatus: moderationStatus.rawValue,
            likeCount: likeCount,
            likeState: likeState.rawValue
        )
    }
}

extension Event {
    init(dto: EventDTO) {
        self.init(
            id: dto.id,
            title: dto.title,
            summary: dto.summary,
            details: dto.details,
            city: dto.city,
            venue: dto.venue,
            imageURL: dto.imageURL,
            startDate: dto.startDate,
            endDate: dto.endDate,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            capacity: dto.capacity,
            registeredCount: dto.registeredCount,
            comments: dto.comments.map {
                Comment(
                    id: $0.id,
                    authorName: $0.authorName,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            moderationStatus: ModerationStatus(rawValue: dto.moderationStatus) ?? .draft,
            registrationState: EventRegistrationState(rawValue: dto.registrationState) ?? .notRegistered,
            likeCount: dto.likeCount,
            likeState: LikeState(rawValue: dto.likeState) ?? .notLiked
        )
    }

    var dto: EventDTO {
        EventDTO(
            id: id,
            title: title,
            summary: summary,
            details: details,
            city: city,
            venue: venue,
            imageURL: imageURL,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            capacity: capacity,
            registeredCount: registeredCount,
            comments: comments.map(\.dto),
            moderationStatus: moderationStatus.rawValue,
            registrationState: registrationState.rawValue,
            likeCount: likeCount,
            likeState: likeState.rawValue
        )
    }
}

extension Organization {
    init(dto: OrganizationDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            description: dto.description,
            city: dto.city,
            imageURL: dto.imageURL,
            contactEmail: dto.contactEmail,
            website: dto.website,
            createdAt: dto.createdAt,
            moderationStatus: ModerationStatus(rawValue: dto.moderationStatus) ?? .draft,
            likeCount: dto.likeCount,
            likeState: LikeState(rawValue: dto.likeState) ?? .notLiked
        )
    }

    var dto: OrganizationDTO {
        OrganizationDTO(
            id: id,
            name: name,
            description: description,
            city: city,
            imageURL: imageURL,
            contactEmail: contactEmail,
            website: website,
            createdAt: createdAt,
            moderationStatus: moderationStatus.rawValue,
            likeCount: likeCount,
            likeState: likeState.rawValue
        )
    }
}

extension MarketplaceItem {
    init(dto: MarketplaceItemDTO) {
        self.init(
            id: dto.id,
            title: dto.title,
            description: dto.description,
            city: dto.city,
            price: dto.price,
            isFreeGift: dto.isFreeGift,
            expirationDate: dto.expirationDate,
            sellerName: dto.sellerName,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            contactValue: dto.contactValue,
            contactMethod: MarketplaceContactMethod(rawValue: dto.contactMethod) ?? .email,
            comments: dto.comments.map {
                Comment(
                    id: $0.id,
                    authorName: $0.authorName,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            moderationStatus: ModerationStatus(rawValue: dto.moderationStatus) ?? .draft,
            likeCount: dto.likeCount,
            likeState: LikeState(rawValue: dto.likeState) ?? .notLiked
        )
    }

    var dto: MarketplaceItemDTO {
        MarketplaceItemDTO(
            id: id,
            title: title,
            description: description,
            city: city,
            price: price,
            isFreeGift: isFreeGift,
            expirationDate: expirationDate,
            sellerName: sellerName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            contactValue: contactValue,
            contactMethod: contactMethod.rawValue,
            comments: comments.map(\.dto),
            moderationStatus: moderationStatus.rawValue,
            likeCount: likeCount,
            likeState: likeState.rawValue
        )
    }
}
