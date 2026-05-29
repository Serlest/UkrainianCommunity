import Foundation

extension GuideArticleDraft {
    nonisolated func makeGuideArticle(
        id: String = UUID().uuidString,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdBy: String,
        updatedBy: String? = nil
    ) throws -> GuideArticle {
        guard let category else {
            throw AppError.validationFailed
        }

        return GuideArticle(
            id: id,
            title: title,
            summary: summary,
            body: body,
            category: category,
            regionScope: federalState == nil ? .austria : .federalState,
            federalState: federalState,
            city: nil,
            officialSourceURL: primarySourceLink?.url,
            sourceName: primarySourceLink?.sourceName,
            isPinned: false,
            moderationStatus: .draft,
            createdAt: createdAt,
            updatedAt: updatedAt,
            contentType: contentType,
            status: .draft,
            contentBlocks: contentBlocks,
            audience: audience,
            sourceLinks: sourceLinks,
            officialSourcesRequired: officialSourcesRequired,
            priority: priority,
            isFeatured: isFeatured,
            createdBy: createdBy,
            updatedBy: updatedBy,
            reviewedBy: nil,
            publishedAt: nil,
            lastReviewedAt: nil,
            nextReviewAt: nil,
            reviewInterval: reviewInterval,
            archivedAt: nil
        )
    }

    nonisolated func updatingGuideArticle(
        _ existingArticle: GuideArticle,
        editorId: String,
        updatedAt: Date = .now
    ) throws -> GuideArticle {
        guard let category else {
            throw AppError.validationFailed
        }

        return GuideArticle(
            id: existingArticle.id,
            title: title,
            summary: summary,
            body: body,
            category: category,
            regionScope: federalState == nil ? .austria : .federalState,
            federalState: federalState,
            city: existingArticle.city,
            officialSourceURL: primarySourceLink?.url,
            sourceName: primarySourceLink?.sourceName,
            isPinned: existingArticle.isPinned,
            moderationStatus: existingArticle.moderationStatus,
            createdAt: existingArticle.createdAt,
            updatedAt: updatedAt,
            contentType: contentType,
            status: existingArticle.status ?? .draft,
            contentBlocks: contentBlocks,
            audience: audience,
            sourceLinks: sourceLinks,
            officialSourcesRequired: officialSourcesRequired,
            priority: priority,
            isFeatured: isFeatured,
            createdBy: existingArticle.createdBy,
            updatedBy: editorId,
            reviewedBy: existingArticle.reviewedBy,
            publishedAt: existingArticle.publishedAt,
            lastReviewedAt: existingArticle.lastReviewedAt,
            nextReviewAt: existingArticle.nextReviewAt,
            reviewInterval: reviewInterval,
            archivedAt: existingArticle.archivedAt
        )
    }

    private nonisolated var primarySourceLink: GuideSourceLink? {
        sourceLinks.first { $0.isRenderable }
    }
}

extension GuideArticle {
    nonisolated func archivedBy(editorId: String, archivedAt: Date = .now) -> GuideArticle {
        GuideArticle(
            id: id,
            title: title,
            summary: summary,
            body: body,
            category: category,
            regionScope: regionScope,
            federalState: federalState,
            city: city,
            officialSourceURL: officialSourceURL,
            sourceName: sourceName,
            isPinned: isPinned,
            moderationStatus: .archived,
            createdAt: createdAt,
            updatedAt: archivedAt,
            contentType: contentType,
            status: .archived,
            contentBlocks: contentBlocks,
            audience: audience,
            sourceLinks: sourceLinks,
            officialSourcesRequired: officialSourcesRequired,
            priority: priority,
            isFeatured: isFeatured,
            createdBy: createdBy,
            updatedBy: editorId,
            reviewedBy: reviewedBy,
            publishedAt: publishedAt,
            lastReviewedAt: lastReviewedAt,
            nextReviewAt: nextReviewAt,
            reviewInterval: reviewInterval,
            archivedAt: archivedAt
        )
    }
}
