import FirebaseFirestore
import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct OrganizationFirestoreWriteContractTests {
    // The production failure involved this microsecond-precision submission date.
    private let originalSubmission = Timestamp(seconds: 1_788_440_797, nanoseconds: 184_433_000)

    @Test func approvedEditDoesNotRoundTripTheProtectedSubmissionTimestamp() {
        let organization = fixture(status: .approved)
        let roundTripped = Timestamp(date: organization.submittedAt!)
        #expect(roundTripped.nanoseconds != originalSubmission.nanoseconds)

        let data = FirestoreOrganizationRepository.makeSafeOrganizationInfoUpdateData(from: organization)
        #expect(data["submittedAt"] == nil)
        #expect(data["reviewMessage"] == nil)
        #expect(data["rejectionReason"] == nil)
        #expect(data["name"] as? String == organization.name)
        #expect(data["moderationStatus"] as? String == "approved")
        #expect(data["updatedAt"] as? Timestamp == Timestamp(date: organization.updatedAt))
    }

    @Test(arguments: [ModerationStatus.draft, .approved, .archived])
    func profileEditsNeverWriteOrDeleteRequestMetadata(status: ModerationStatus) {
        for hasSubmission in [true, false] {
            let data = FirestoreOrganizationRepository.makeSafeOrganizationInfoUpdateData(
                from: fixture(status: status, hasSubmission: hasSubmission)
            )
            for key in ["submittedAt", "reviewMessage", "rejectionReason"] {
                #expect(!data.keys.contains(key))
            }
        }
    }

    @Test(arguments: [ModerationStatus.pendingReview, .needsRevision, .rejected])
    func requestEditsKeepTheirSeparateMetadataContract(status: ModerationStatus) {
        let organization = fixture(status: status)
        let data = FirestoreOrganizationRepository.makeSafeOrganizationInfoUpdateData(from: organization)
        #expect(data["submittedAt"] as? Timestamp == Timestamp(date: organization.submittedAt!))
        #expect(data["reviewMessage"] as? String == organization.reviewMessage)
        #expect(data["rejectionReason"] as? String == organization.rejectionReason)
        #expect(data["moderationStatus"] as? String == status.rawValue)
    }

    @Test func editableOptionalFieldsCanStillBeClearedWithoutChangingOwnershipOrCounters() {
        let organization = fixture(status: .approved)
        let data = FirestoreOrganizationRepository.makeSafeOrganizationInfoUpdateData(from: organization)
        for key in ["website", "phone", "contactPerson"] {
            #expect((data[key] as? FieldValue)?.isEqual(FieldValue.delete()) == true)
        }
        for key in [
            "id", "ownerId", "adminIds", "moderatorIds", "createdAt", "submittedByUserId",
            "submittedByDisplayName", "reviewedAt", "reviewedByUserId", "isSystemManaged", "sourceType",
            "subscriberCount", "likeCount", "eventsHeldCount", "volunteersCount", "helpedPeopleCount",
            "pinnedNewsId", "pinnedEventId",
        ] {
            #expect(!data.keys.contains(key))
        }
        let profile = data["directoryProfile"] as? [String: Any]
        #expect(profile?["profileKind"] as? String == "institution")
        #expect(profile?["serviceArea"] as? String == "Tirol")
    }

    @Test func initialRequestCreationStillIncludesSubmissionMetadata() {
        let organization = fixture(status: .pendingReview)
        let data = FirestoreOrganizationRepository.makeOrganizationData(from: organization)
        #expect(data["submittedByUserId"] as? String == organization.submittedByUserId)
        #expect(data["submittedAt"] as? Timestamp == Timestamp(date: organization.submittedAt!))
        #expect(data["moderationStatus"] as? String == "pendingReview")
        #expect(data["directoryProfile"] is [String: Any])
    }

    @Test(arguments: [ModerationStatus.needsRevision, .rejected])
    func editorResubmissionStillRefreshesDateAndClearsReviewMessages(status: ModerationStatus) async throws {
        let repository = MockOrganizationRepository()
        let organization = fixture(status: status)
        try await repository.createOrganization(organization)
        let viewModel = OrganizationsViewModel(repository: repository)
        let editor = OrganizationEditorViewModel(mode: .edit(existing: organization))
        let submitted = await editor.submit(with: viewModel, user: MockContentBuilder.currentUser())
        #expect(submitted)
        let saved = try await repository.fetchOrganization(id: organization.id)
        try await repository.deleteOrganization(id: organization.id)

        #expect(saved.moderationStatus == .pendingReview)
        #expect(saved.submittedAt != organization.submittedAt)
        #expect(saved.reviewMessage == nil)
        #expect(saved.rejectionReason == nil)
        #expect(saved.reviewedAt == organization.reviewedAt)
        #expect(saved.reviewedByUserId == organization.reviewedByUserId)
        let data = FirestoreOrganizationRepository.makeSafeOrganizationInfoUpdateData(from: saved)
        #expect(data["submittedAt"] as? Timestamp == Timestamp(date: saved.submittedAt!))
        for key in ["reviewMessage", "rejectionReason"] {
            #expect((data[key] as? FieldValue)?.isEqual(FieldValue.delete()) == true)
        }
        #expect(data["reviewedAt"] == nil)
        #expect(data["reviewedByUserId"] == nil)
    }

    private func fixture(status: ModerationStatus, hasSubmission: Bool = true) -> Organization {
        let date = originalSubmission.dateValue()
        return Organization(
            id: "org-write-contract-\(UUID().uuidString)",
            name: "Community institution",
            description: "A sufficiently detailed description of this community institution.",
            city: "Innsbruck",
            organizationType: "support",
            directoryProfile: OrganizationDirectoryProfile(profileKind: .institution, serviceArea: "Tirol"),
            ownerId: status == .approved ? MockContentBuilder.currentUser().id : nil,
            submittedByUserId: hasSubmission ? MockContentBuilder.currentUser().id : nil,
            submittedAt: hasSubmission ? date : nil,
            reviewMessage: hasSubmission ? "Please complete the description" : nil,
            reviewedByUserId: hasSubmission ? "reviewer" : nil,
            reviewedAt: hasSubmission ? date : nil,
            rejectionReason: hasSubmission ? "Missing information" : nil,
            createdAt: date,
            updatedAt: date.addingTimeInterval(60),
            moderationStatus: status,
            likeCount: 0,
            likeState: .notLiked
        )
    }
}
