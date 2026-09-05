package at.uac.android

import at.uac.android.feature.inbox.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class InboxNavigationTest {
    @Test
    fun statementRouteIsPrivateAndDoesNotGrantOwnerAccess() {
        val value = notice.copy(actionType = "dsaStatement", actionTargetId = "statement-1")
        assertEquals(
            InboxNavigationTarget.Route("profile/dsa-statement/statement-1"),
            resolve(value),
        )
        assertEquals(resolve(value), resolve(value, manager = true))
        assertNull(resolve(value, current = session.copy(uid = "other")))
        assertNull(resolve(value, current = session.copy(revision = 8)))
    }

    @Test
    fun statementRoutesRejectAliasesAndMalformedTargetsBeforeNavigation() {
        for (id in listOf("bad/path", "a b", "a\uFEFFb", "a".repeat(201), "..", "\uD800")) {
            assertFalse(
                availableInboxDestination(InboxDestination(InboxDestinationKind.DSA_STATEMENT, id))
            )
            assertNull(resolve(notice.copy(actionType = "dsaStatement", actionTargetId = id)))
        }
        assertFalse(availableInboxDestination(InboxDestination(InboxDestinationKind.DSA_STATEMENT)))
    }

    private val now = Instant.parse("2026-09-03T01:00:00Z")
    private val session = InboxSession("synthetic-alice", 7, true)
    private val notice =
        InboxNotice(
            "notice",
            session.uid,
            InboxKind.NEWS,
            now,
            false,
            actionType = "openNews",
            actionTargetId = "news-1",
        )

    private fun resolve(
        value: InboxNotice = notice,
        current: InboxSession? = session,
        manager: Boolean = false,
        destination: InboxDestination? = value.destination(now),
    ) = destination?.let {
        resolveInboxNavigation(value, it, session, current, manager, now)
    }

    @Test
    fun publicRouteRequiresContentReload() {
        assertEquals(InboxNavigationTarget.Route("news/news-1", true), resolve())
    }

    @Test
    fun accountAndRevisionChangesRejectCapturedNavigation() {
        assertNull(resolve(current = null))
        assertNull(resolve(current = session.copy(uid = "synthetic-bob")))
        assertNull(resolve(current = session.copy(revision = 8)))
        assertNull(resolve(current = session.copy(canEditPreferences = false)))
        assertNull(resolve(notice.copy(uid = "synthetic-bob")))
    }

    @Test
    fun expirationDeletionAndForgedDestinationFailClosed() {
        val captured = notice.destination(now)!!
        assertNull(resolve(notice.copy(expiresAt = now), destination = captured))
        assertNull(resolve(notice.copy(deletedAt = now), destination = captured))
        assertNull(resolve(destination = captured.copy(target = "news-2")))
        assertNull(resolve(notice.copy(actionTargetId = "../private")))
    }

    @Test
    fun feedbackManagementUsesLiveRoleAndNoticeKind() {
        val submitted =
            notice.copy(
                kind = InboxKind.FEEDBACK_SUBMITTED,
                actionType = "openFeedback",
                actionTargetId = "feedback-1",
            )
        assertEquals(
            InboxNavigationTarget.Route("profile/support/feedback-1"),
            resolve(submitted, manager = true),
        )
        assertEquals(
            InboxNavigationTarget.Route("profile/feedback/feedback-1"),
            resolve(submitted, manager = false),
        )
        assertEquals(
            InboxNavigationTarget.Route("profile/feedback/feedback-1"),
            resolve(submitted.copy(kind = InboxKind.FEEDBACK_REPLY), manager = true),
        )
    }

    @Test
    fun missingOptionalTargetsOpenListsNotLiteralNullDocuments() {
        assertEquals(
            InboxNavigationTarget.Route("profile/feedback"),
            resolve(notice.copy(actionType = "openFeedback", actionTargetId = null)),
        )
        assertEquals(
            InboxNavigationTarget.Route("profile/organizations"),
            resolve(notice.copy(actionType = "openOrganizationRequest", actionTargetId = null)),
        )
    }

    @Test
    fun externalDestinationIsSeparateFromInternalRoute() {
        val url = "https://example.invalid/verified"
        assertEquals(
            InboxNavigationTarget.External(url),
            resolve(notice.copy(actionType = "openURL", actionTargetId = url)),
        )
        assertNull(
            resolve(notice.copy(actionType = "openURL", actionTargetId = "javascript:alert(1)"))
        )
    }

    @Test
    fun statementAliasIsAvailableWhileUnresolvedPlanningRemainsUnavailable() {
        assertEquals(
            InboxNavigationTarget.Route("profile/dsa-statement/statement-1"),
            resolve(notice.copy(actionType = "openDsaStatement", actionTargetId = "statement-1")),
        )
        assertNull(
            resolve(notice.copy(actionType = "openContentPlanning", actionTargetId = "draft-1"))
        )
    }

    @Test
    fun previouslyArchivedInboxItemsRetainTheirReadOnlyDestination() {
        // Build 65 keeps archived inbox rows visible; the popup coordinator excludes them
        // separately.
        assertEquals(
            InboxNavigationTarget.Route("news/news-1", true),
            resolve(notice.copy(archivedAt = now)),
        )
    }
}
