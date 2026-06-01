import Foundation

struct UserDTO: Codable, Identifiable {
    let id: String
    let fullName: String
    let displayName: String?
    let city: String
    let email: String
    let avatarURL: String?
    let bio: String
    let telegramUsername: String?
    let role: String?
    let blockState: String
    let globalRole: String?
    let moderatorSections: [String]?
    let canManageGuide: Bool?
    let accountStatus: String?
    let banExpiresAt: Date?
    let warningCount: Int?
    let communityMemberships: [CommunityMembershipDTO]?
    let selectedFederalState: String?
    let acceptedTermsAt: Date?
    let acceptedPrivacyAt: Date?
    let termsVersion: String?
    let privacyVersion: String?
    let createdAt: Date
    let updatedAt: Date
}

struct FeedbackDTO: Codable, Identifiable {
    let id: String
    let type: String
    let subject: String?
    let message: String
    let status: String
    let createdAt: Date
    let updatedAt: Date?
    let userId: String
    let userDisplayName: String
    let ownerReply: String?
    let repliedAt: Date?
    let repliedByUserId: String?
    let lastMessageText: String?
    let lastMessageAt: Date?
    let lastMessageByUserId: String?
    let lastMessageByRole: String?
    let unreadForOwner: Bool?
    let unreadForUser: Bool?
}

struct CommunityMembershipDTO: Codable, Identifiable {
    let organizationId: String
    let role: String

    var id: String { organizationId }
}

struct CommentDTO: Codable, Identifiable {
    let id: String
    let parentType: String?
    let parentId: String?
    let authorId: String?
    let authorName: String
    let authorPhotoURL: String?
    let text: String
    let createdAt: Date
    let updatedAt: Date?
    let moderationStatus: String?
    let isDeleted: Bool?

    var body: String { text }

    nonisolated init(
        id: String,
        parentType: String? = nil,
        parentId: String? = nil,
        authorId: String? = nil,
        authorName: String,
        authorPhotoURL: String? = nil,
        text: String? = nil,
        body: String? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        moderationStatus: String? = ModerationStatus.approved.rawValue,
        isDeleted: Bool? = false
    ) {
        self.id = id
        self.parentType = parentType
        self.parentId = parentId
        self.authorId = authorId
        self.authorName = authorName
        self.authorPhotoURL = authorPhotoURL
        self.text = text ?? body ?? ""
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.moderationStatus = moderationStatus
        self.isDeleted = isDeleted
    }
}

struct NewsPostDTO: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let regionScope: String?
    let federalState: String?
    let city: String?
    let category: String?
    let tags: [String]?
    let sourceType: String?
    let organizationId: String?
    let organizationName: String?
    let organizationImageURL: String?
    let sourceName: String?
    let sourceURL: String?
    let imageURL: String?
    let body: String
    let authorName: String
    let publishedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let comments: [CommentDTO]
    let commentCount: Int?
    let moderationStatus: String
    let likeCount: Int
    let likeState: String
    let viewCount: Int
    let isBookmarked: Bool
}

struct EventDTO: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let details: String
    let regionScope: String?
    let federalState: String?
    let sourceType: String?
    let organizationId: String?
    let organizationName: String?
    let organizationImageURL: String?
    let authorId: String?
    let authorName: String?
    let city: String
    let venue: String
    let address: String?
    let locationNote: String?
    let latitude: Double?
    let longitude: Double?
    let organizerName: String?
    let organizerURL: String?
    let contactPhone: String?
    let contactEmail: String?
    let contactURL: String?
    let imageURL: String?
    let startDate: Date
    let endDate: Date
    let createdAt: Date
    let updatedAt: Date
    let requiresRegistration: Bool?
    let price: Double
    let capacity: Int?
    let registeredCount: Int
    let comments: [CommentDTO]
    let commentCount: Int?
    let moderationStatus: String
    let registrationState: String
    let likeCount: Int
    let likeState: String
    let viewCount: Int
    let category: String?
    let tags: [String]?
    let visibility: String?
    let isAllDay: Bool?
    let isBookmarked: Bool
}

struct OrganizationDTO: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let shortDescription: String?
    let fullDescription: String?
    let regionScope: String?
    let federalState: String?
    let city: String
    let imageURL: String?
    let logoURL: String?
    let coverURL: String?
    let contactEmail: String?
    let email: String?
    let phone: String?
    let website: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let organizationType: String?
    let foundedYear: Int?
    let foundedMonth: Int?
    let languages: [String]?
    let socialLinks: [String: String]?
    let telegramURL: String?
    let donationURL: String?
    let facebookURL: String?
    let instagramURL: String?
    let whatsappURL: String?
    let youtubeURL: String?
    let linkedinURL: String?
    let missionStatement: String?
    let contactPerson: String?
    let subscriberCount: Int
    let eventsHeldCount: Int
    let volunteersCount: Int
    let helpedPeopleCount: Int
    let ownerId: String?
    let adminIds: [String]
    let moderatorIds: [String]
    let isSystemManaged: Bool?
    let sourceType: String?
    let pinnedNewsId: String?
    let pinnedEventId: String?
    let submittedByUserId: String?
    let submittedByDisplayName: String?
    let submittedAt: Date?
    let reviewMessage: String?
    let reviewedByUserId: String?
    let reviewedAt: Date?
    let rejectionReason: String?
    let createdAt: Date
    let updatedAt: Date
    let moderationStatus: String
    let likeCount: Int
    let likeState: String
    let isSubscribed: Bool
    let isBookmarked: Bool
}

extension AppUser {
    init(dto: UserDTO) {
        let legacyRole = UserRole(rawValue: dto.role ?? "") ?? .user
        let resolvedGlobalRole = dto.globalRole.flatMap(GlobalRole.init(rawValue:)) ?? .user
        let resolvedModeratorSections = (dto.moderatorSections ?? []).compactMap(AppSection.init(rawValue:))
        let resolvedBlockState = UserBlockState(rawValue: dto.blockState) ?? .active
        let resolvedAccountStatus = dto.accountStatus.flatMap(AccountStatus.init(rawValue:))
            ?? (resolvedBlockState.isRestricted ? .suspendedUntil : .active)

        self.init(
            id: dto.id,
            fullName: dto.fullName,
            displayName: dto.displayName ?? dto.fullName,
            city: dto.city,
            email: dto.email,
            avatarURL: dto.avatarURL.flatMap(URL.init(string:)),
            bio: dto.bio,
            telegramUsername: dto.telegramUsername,
            role: legacyRole,
            globalRole: resolvedGlobalRole,
            moderatorSections: resolvedModeratorSections,
            canManageGuide: dto.canManageGuide ?? false,
            blockState: resolvedBlockState,
            accountStatus: resolvedAccountStatus,
            banExpiresAt: dto.banExpiresAt,
            warningCount: dto.warningCount ?? 0,
            communityMemberships: (dto.communityMemberships ?? []).map {
                CommunityMembership(
                    organizationId: $0.organizationId,
                    role: CommunityRole(rawValue: $0.role) ?? .member
                )
            },
            selectedFederalState: dto.selectedFederalState.flatMap(AustrianFederalState.init(rawValue:)) ?? .tirol,
            acceptedTermsAt: dto.acceptedTermsAt,
            acceptedPrivacyAt: dto.acceptedPrivacyAt,
            termsVersion: dto.termsVersion,
            privacyVersion: dto.privacyVersion,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    var dto: UserDTO {
        UserDTO(
            id: id,
            fullName: fullName,
            displayName: displayName,
            city: city,
            email: email,
            avatarURL: avatarURL?.absoluteString,
            bio: bio,
            telegramUsername: telegramUsername,
            role: nil,
            blockState: blockState.rawValue,
            globalRole: globalRole.rawValue,
            moderatorSections: moderatorSections.map(\.rawValue),
            canManageGuide: canManageGuide,
            accountStatus: accountStatus.rawValue,
            banExpiresAt: banExpiresAt,
            warningCount: warningCount,
            communityMemberships: communityMemberships.map {
                CommunityMembershipDTO(
                    organizationId: $0.organizationId,
                    role: $0.role.rawValue
                )
            },
            selectedFederalState: selectedFederalState?.rawValue,
            acceptedTermsAt: acceptedTermsAt,
            acceptedPrivacyAt: acceptedPrivacyAt,
            termsVersion: termsVersion,
            privacyVersion: privacyVersion,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension FeedbackItem {
    init(dto: FeedbackDTO) {
        self.init(
            id: dto.id,
            type: FeedbackType(rawValue: dto.type) ?? .question,
            subject: dto.subject,
            message: dto.message,
            status: FeedbackStatus(rawValue: dto.status) ?? .open,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt ?? dto.createdAt,
            userId: dto.userId,
            userDisplayName: dto.userDisplayName,
            ownerReply: dto.ownerReply,
            repliedAt: dto.repliedAt,
            repliedByUserId: dto.repliedByUserId,
            lastMessageText: dto.lastMessageText,
            lastMessageAt: dto.lastMessageAt,
            lastMessageByUserId: dto.lastMessageByUserId,
            lastMessageByRole: dto.lastMessageByRole.flatMap(FeedbackSenderRole.init(rawValue:)),
            unreadForOwner: dto.unreadForOwner ?? false,
            unreadForUser: dto.unreadForUser ?? false
        )
    }

    var dto: FeedbackDTO {
        FeedbackDTO(
            id: id,
            type: type.rawValue,
            subject: subject,
            message: message,
            status: status.rawValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            userId: userId,
            userDisplayName: userDisplayName,
            ownerReply: ownerReply,
            repliedAt: repliedAt,
            repliedByUserId: repliedByUserId,
            lastMessageText: lastMessageText,
            lastMessageAt: lastMessageAt,
            lastMessageByUserId: lastMessageByUserId,
            lastMessageByRole: lastMessageByRole?.rawValue,
            unreadForOwner: unreadForOwner,
            unreadForUser: unreadForUser
        )
    }
}

extension Comment {
    nonisolated init(dto: CommentDTO) {
        self.init(
            id: dto.id,
            parentType: dto.parentType.flatMap(CommentParentType.init(rawValue:)),
            parentId: dto.parentId,
            authorId: dto.authorId,
            authorName: dto.authorName,
            authorPhotoURL: dto.authorPhotoURL,
            text: dto.text,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            moderationStatus: dto.moderationStatus.flatMap(ModerationStatus.init(rawValue:)) ?? .approved,
            isDeleted: dto.isDeleted ?? false
        )
    }

    var dto: CommentDTO {
        CommentDTO(
            id: id,
            parentType: parentType?.rawValue,
            parentId: parentId,
            authorId: authorId,
            authorName: authorName,
            authorPhotoURL: authorPhotoURL,
            text: text,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus.rawValue,
            isDeleted: isDeleted
        )
    }
}

extension NewsPost {
    init(dto: NewsPostDTO) {
        self.init(
            id: dto.id,
            title: dto.title,
            subtitle: dto.subtitle,
            regionScope: dto.regionScope.flatMap(RegionScope.init(rawValue:)) ?? .federalState,
            federalState: dto.federalState.flatMap(AustrianFederalState.init(rawValue:)) ?? .tirol,
            city: dto.city,
            category: dto.category.flatMap(NewsCategory.init(rawValue:)) ?? .news,
            tags: dto.tags ?? [],
            source: ContentSourceMetadata(
                sourceType: dto.sourceType.flatMap(ContentSourceType.init(rawValue:)) ?? .app,
                organizationId: dto.organizationId,
                organizationName: dto.organizationName,
                organizationImageURL: dto.organizationImageURL
            ),
            sourceName: dto.sourceName,
            sourceURL: dto.sourceURL,
            imageURL: dto.imageURL,
            body: dto.body,
            authorName: dto.authorName,
            publishedAt: dto.publishedAt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            comments: dto.comments.map(Comment.init(dto:)),
            moderationStatus: ModerationStatus(rawValue: dto.moderationStatus) ?? .draft,
            likeCount: dto.likeCount,
            likeState: LikeState(rawValue: dto.likeState) ?? .notLiked,
            viewCount: dto.viewCount,
            isBookmarked: dto.isBookmarked,
            commentCount: dto.commentCount
        )
    }

    var dto: NewsPostDTO {
        NewsPostDTO(
            id: id,
            title: title,
            subtitle: subtitle,
            regionScope: regionScope?.rawValue,
            federalState: federalState?.rawValue,
            city: city,
            category: category.rawValue,
            tags: tags,
            sourceType: source.sourceType.rawValue,
            organizationId: source.organizationId,
            organizationName: source.organizationName,
            organizationImageURL: source.organizationImageURL,
            sourceName: sourceName,
            sourceURL: sourceURL,
            imageURL: imageURL,
            body: body,
            authorName: authorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            comments: comments.map(\.dto),
            commentCount: commentCount,
            moderationStatus: moderationStatus.rawValue,
            likeCount: likeCount,
            likeState: likeState.rawValue,
            viewCount: viewCount,
            isBookmarked: isBookmarked
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
            regionScope: dto.regionScope.flatMap(RegionScope.init(rawValue:)) ?? .city,
            federalState: dto.federalState.flatMap(AustrianFederalState.init(rawValue:)) ?? .tirol,
            source: ContentSourceMetadata(
                sourceType: dto.sourceType.flatMap(ContentSourceType.init(rawValue:)) ?? .app,
                organizationId: dto.organizationId,
                organizationName: dto.organizationName,
                organizationImageURL: dto.organizationImageURL
            ),
            authorId: dto.authorId,
            authorName: dto.authorName,
            city: dto.city,
            venue: dto.venue,
            address: dto.address,
            locationNote: dto.locationNote,
            latitude: dto.latitude,
            longitude: dto.longitude,
            organizerName: dto.organizerName,
            organizerURL: dto.organizerURL,
            contactPhone: dto.contactPhone,
            contactEmail: dto.contactEmail,
            contactURL: dto.contactURL,
            imageURL: dto.imageURL,
            startDate: dto.startDate,
            endDate: dto.endDate,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            requiresRegistration: dto.requiresRegistration ?? true,
            price: dto.price,
            capacity: dto.capacity,
            registeredCount: dto.registeredCount,
            comments: dto.comments.map(Comment.init(dto:)),
            moderationStatus: ModerationStatus(rawValue: dto.moderationStatus) ?? .draft,
            registrationState: EventRegistrationState(rawValue: dto.registrationState) ?? .notRegistered,
            likeCount: dto.likeCount,
            likeState: LikeState(rawValue: dto.likeState) ?? .notLiked,
            viewCount: dto.viewCount,
            category: dto.category.flatMap(EventCategory.init(rawValue:)) ?? .unspecified,
            tags: dto.tags ?? [],
            isAllDay: dto.isAllDay ?? false,
            isBookmarked: dto.isBookmarked,
            commentCount: dto.commentCount
        )
    }

    var dto: EventDTO {
        EventDTO(
            id: id,
            title: title,
            summary: summary,
            details: details,
            regionScope: regionScope?.rawValue,
            federalState: federalState?.rawValue,
            sourceType: source.sourceType.rawValue,
            organizationId: source.organizationId,
            organizationName: source.organizationName,
            organizationImageURL: source.organizationImageURL,
            authorId: authorId,
            authorName: authorName,
            city: city,
            venue: venue,
            address: address,
            locationNote: locationNote,
            latitude: latitude,
            longitude: longitude,
            organizerName: organizerName,
            organizerURL: organizerURL,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            contactURL: contactURL,
            imageURL: imageURL,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            requiresRegistration: requiresRegistration,
            price: price,
            capacity: capacity,
            registeredCount: registeredCount,
            comments: comments.map(\.dto),
            commentCount: commentCount,
            moderationStatus: moderationStatus.rawValue,
            registrationState: registrationState.rawValue,
            likeCount: likeCount,
            likeState: likeState.rawValue,
            viewCount: viewCount,
            category: category.rawValue,
            tags: tags,
            visibility: "public",
            isAllDay: isAllDay,
            isBookmarked: isBookmarked
        )
    }
}

extension Organization {
    init(dto: OrganizationDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            description: dto.description,
            shortDescription: dto.shortDescription,
            fullDescription: dto.fullDescription,
            regionScope: dto.regionScope.flatMap(RegionScope.init(rawValue:)) ?? .city,
            federalState: dto.federalState.flatMap(AustrianFederalState.init(rawValue:)) ?? .tirol,
            city: dto.city,
            imageURL: dto.imageURL,
            logoURL: dto.logoURL,
            coverURL: dto.coverURL,
            contactEmail: dto.contactEmail,
            email: dto.email,
            phone: dto.phone,
            website: dto.website,
            address: dto.address,
            latitude: dto.latitude,
            longitude: dto.longitude,
            organizationType: dto.organizationType,
            foundedYear: dto.foundedYear,
            foundedMonth: dto.foundedMonth,
            languages: dto.languages ?? [],
            socialLinks: dto.socialLinks ?? [:],
            telegramURL: dto.telegramURL,
            donationURL: dto.donationURL,
            facebookURL: dto.facebookURL,
            instagramURL: dto.instagramURL,
            whatsappURL: dto.whatsappURL,
            youtubeURL: dto.youtubeURL,
            linkedinURL: dto.linkedinURL,
            missionStatement: dto.missionStatement,
            contactPerson: dto.contactPerson,
            subscriberCount: dto.subscriberCount,
            eventsHeldCount: dto.eventsHeldCount,
            volunteersCount: dto.volunteersCount,
            helpedPeopleCount: dto.helpedPeopleCount,
            ownerId: dto.ownerId,
            adminIds: dto.adminIds,
            moderatorIds: dto.moderatorIds,
            isSystemManaged: dto.isSystemManaged,
            sourceType: dto.sourceType.flatMap(ContentSourceType.init(rawValue:)),
            pinnedNewsId: dto.pinnedNewsId,
            pinnedEventId: dto.pinnedEventId,
            submittedByUserId: dto.submittedByUserId,
            submittedByDisplayName: dto.submittedByDisplayName,
            submittedAt: dto.submittedAt,
            reviewMessage: dto.reviewMessage,
            reviewedByUserId: dto.reviewedByUserId,
            reviewedAt: dto.reviewedAt,
            rejectionReason: dto.rejectionReason,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            moderationStatus: ModerationStatus(rawValue: dto.moderationStatus) ?? .draft,
            likeCount: dto.likeCount,
            likeState: LikeState(rawValue: dto.likeState) ?? .notLiked,
            isSubscribed: dto.isSubscribed,
            isBookmarked: dto.isBookmarked
        )
    }

    var dto: OrganizationDTO {
        OrganizationDTO(
            id: id,
            name: name,
            description: description,
            shortDescription: shortDescription,
            fullDescription: fullDescription,
            regionScope: regionScope?.rawValue,
            federalState: federalState?.rawValue,
            city: city,
            imageURL: imageURL,
            logoURL: logoURL,
            coverURL: coverURL,
            contactEmail: contactEmail,
            email: email,
            phone: phone,
            website: website,
            address: address,
            latitude: latitude,
            longitude: longitude,
            organizationType: organizationType,
            foundedYear: foundedYear,
            foundedMonth: foundedMonth,
            languages: languages,
            socialLinks: socialLinks,
            telegramURL: telegramURL,
            donationURL: donationURL,
            facebookURL: facebookURL,
            instagramURL: instagramURL,
            whatsappURL: whatsappURL,
            youtubeURL: youtubeURL,
            linkedinURL: linkedinURL,
            missionStatement: missionStatement,
            contactPerson: contactPerson,
            subscriberCount: subscriberCount,
            eventsHeldCount: eventsHeldCount,
            volunteersCount: volunteersCount,
            helpedPeopleCount: helpedPeopleCount,
            ownerId: ownerId,
            adminIds: adminIds,
            moderatorIds: moderatorIds,
            isSystemManaged: isSystemManaged,
            sourceType: sourceType?.rawValue,
            pinnedNewsId: pinnedNewsId,
            pinnedEventId: pinnedEventId,
            submittedByUserId: submittedByUserId,
            submittedByDisplayName: submittedByDisplayName,
            submittedAt: submittedAt,
            reviewMessage: reviewMessage,
            reviewedByUserId: reviewedByUserId,
            reviewedAt: reviewedAt,
            rejectionReason: rejectionReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus.rawValue,
            likeCount: likeCount,
            likeState: likeState.rawValue,
            isSubscribed: isSubscribed,
            isBookmarked: isBookmarked
        )
    }
}
