import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AccountStatusNoticeTests {
    private let changedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private func user(_ status: AccountStatus, _ block: UserBlockState,
                      acknowledgedAt: Date? = nil, id: String = "selected-user") -> AppUser {
        AppUser(id: id, fullName: "Selected User", displayName: "Selected", city: "Wien",
                email: "selected@example.test", bio: "", role: .user, blockState: block,
                accountStatus: status, banExpiresAt: changedAt.addingTimeInterval(86400),
                statusReason: "  Specific violation  ", statusUpdatedAt: changedAt,
                statusUpdatedBy: "owner", statusAcknowledgedAt: acknowledgedAt,
                createdAt: changedAt, updatedAt: changedAt)
    }

    @Test func everyStatusShowsTheAffectedUserAndCorrectExitRequirement() throws {
        let cases: [(AccountStatus, UserBlockState, Bool)] = [
            (.warned, .warned, false), (.active, .active, false),
            (.suspendedUntil, .suspendedUntil, true), (.bannedPermanent, .bannedPermanent, true),
            (.deactivated, .deactivated, true), (.temporarilyBanned, .suspendedUntil, true),
            (.permanentlyBanned, .bannedPermanent, true)
        ]
        for (status, block, mustExit) in cases {
            let notice = try #require(AccountStatusNotice(user: user(status, block)))
            #expect(notice.userID == "selected-user")
            #expect(notice.reason == "Specific violation")
            #expect(notice.requiresSignOut == mustExit)
            #expect(notice.banExpiresAt == changedAt.addingTimeInterval(86400))
        }
    }

    @Test func acknowledgedNoticeDoesNotRepeatAndOldAcknowledgementDoesNotHideNewNotice() {
        #expect(AccountStatusNotice(user: user(.warned, .warned, acknowledgedAt: changedAt)) == nil)
        #expect(AccountStatusNotice(user: user(.warned, .warned, acknowledgedAt: changedAt.addingTimeInterval(-1))) != nil)
        let first = AccountStatusNotice(user: user(.warned, .warned))
        let other = AccountStatusNotice(user: user(.warned, .warned, id: "other-user"))
        #expect(first?.id != other?.id)
    }
}
