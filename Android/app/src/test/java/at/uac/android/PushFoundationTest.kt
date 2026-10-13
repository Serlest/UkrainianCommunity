package at.uac.android

import androidx.lifecycle.SavedStateHandle
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.push.*
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class PushFoundationTest {
    private val session = PushSession("user-a", 7, true)

    private class Store(var value: OwnedPushRegistration? = null) : PushOwnershipStore {
        var saves = 0
        var clears = 0

        override suspend fun load() = value

        override suspend fun save(value: OwnedPushRegistration) {
            saves++
            this.value = value
        }

        override suspend fun clear(expected: OwnedPushRegistration) {
            assertEquals(expected, value)
            clears++
            value = null
        }
    }

    private class Backend : PushRegistrationBackend {
        val writes = mutableListOf<Pair<String, PushRegistration>>()
        val deletes = mutableListOf<Pair<String, PushToken>>()
        var failure: Exception? = null
        var afterWrite: () -> Unit = {}

        override suspend fun upsert(capturedUid: String, registration: PushRegistration) {
            failure?.let { throw it }
            writes += capturedUid to registration
            afterWrite()
        }

        override suspend fun deleteExact(
            capturedUid: String,
            registration: PushRegistration,
        ) {
            failure?.let { throw it }
            deletes += capturedUid to registration.token
        }
    }

    private class Tokens(var raw: String = "token-0123456789-abcdef") : PushTokenSource {
        var installationCalls = 0
        var tokenCalls = 0
        var unregisterCalls = 0

        override suspend fun installationId(): String {
            installationCalls++
            return "installation_1234567890"
        }

        override suspend fun token(): String {
            tokenCalls++
            return raw
        }

        override suspend fun unregister() {
            unregisterCalls++
        }
    }

    private fun coordinator(
        backend: Backend,
        store: Store,
        tokens: Tokens,
        current: () -> PushSession? = { session },
    ) =
        PushCoordinator(
            backend,
            store,
            tokens,
            current,
            { "Pixel" },
            { "1.0.0" },
        )

    @Test
    fun consentAndRuntimePermissionBothGateIdentifierAcquisitionAndRegistration() = runTest {
        for (gate in listOf(PushGate(false, false), PushGate(true, false), PushGate(false, true))) {
            val backend = Backend()
            val store = Store()
            val tokens = Tokens()
            val result = coordinator(backend, store, tokens).reconcile(session, gate)
            assertEquals(PushFailure.PERMISSION, result.failure)
            assertEquals(0, tokens.installationCalls)
            assertEquals(0, tokens.tokenCalls)
            assertEquals(1, tokens.unregisterCalls)
            assertTrue(backend.writes.isEmpty())
        }
    }

    @Test
    fun sameInstallationRotatesInOneStableDocumentAndDeduplicatesSameToken() = runTest {
        val backend = Backend()
        val store = Store()
        val tokens = Tokens()
        val target = coordinator(backend, store, tokens)
        assertTrue(target.reconcile(session, PushGate(true, true)).changed)
        assertFalse(target.reconcile(session, PushGate(true, true)).changed)
        tokens.raw = "rotated-0123456789-abcdef"
        assertTrue(target.reconcile(session, PushGate(true, true)).changed)
        assertEquals(2, backend.writes.size)
        assertEquals(backend.writes[0].second.documentId, backend.writes[1].second.documentId)
        assertNotEquals(backend.writes[0].second.token, backend.writes[1].second.token)
    }

    @Test
    fun capturedSessionRefusesCrossAccountAndRevisionRaces() = runTest {
        val backend = Backend()
        val store = Store()
        val tokens = Tokens()
        val other = session.copy(uid = "user-b")
        assertEquals(
            PushFailure.CROSS_ACCOUNT,
            coordinator(backend, store, tokens) { other }
                .reconcile(session, PushGate(true, true))
                .failure,
        )
        assertEquals(
            PushFailure.STALE_SESSION,
            coordinator(backend, store, tokens) { session.copy(revision = 8) }
                .reconcile(session, PushGate(true, true))
                .failure,
        )
        assertTrue(backend.writes.isEmpty())
        assertEquals(0, tokens.tokenCalls)
    }

    @Test
    fun accountChangeDuringWriteNeverCommitsLocalOwnershipForTheNewSession() = runTest {
        var live = session
        val backend = Backend()
        val store = Store()
        backend.afterWrite = { live = session.copy(uid = "user-b") }
        val result =
            coordinator(backend, store, Tokens()) { live }.reconcile(session, PushGate(true, true))
        assertEquals(PushFailure.CROSS_ACCOUNT, result.failure)
        assertNull(store.value)
        assertEquals("user-a", backend.writes.single().first)
    }

    @Test
    fun persistedDifferentOwnerIsNeverTransferredOrDeleted() = runTest {
        val registration =
            PushRegistrationContract.create(
                "installation_1234567890",
                "token-0123456789-abcdef",
                "Pixel",
                "1.0.0",
            )
        val backend = Backend()
        val store = Store(OwnedPushRegistration("user-b", registration))
        val result = coordinator(backend, store, Tokens()).reconcile(session, PushGate(true, true))
        assertEquals(PushFailure.CROSS_ACCOUNT, result.failure)
        assertTrue(backend.writes.isEmpty())
        assertTrue(backend.deletes.isEmpty())
        assertEquals("user-b", store.value?.uid)
    }

    @Test
    fun logoutDeletesOnlyCapturedCurrentRegistrationAndKeepsRetryStateOnFailure() = runTest {
        val backend = Backend()
        val store = Store()
        val targetTokens = Tokens()
        val target = coordinator(backend, store, targetTokens)
        target.reconcile(session, PushGate(true, true))
        backend.failure = IllegalStateException("offline")
        assertEquals(PushFailure.UNKNOWN, target.beforeLogout(session).failure)
        assertNotNull(store.value)
        backend.failure = null
        assertTrue(target.beforeLogout(session).changed)
        assertEquals(listOf("user-a"), backend.deletes.map { it.first })
        assertEquals(2, targetTokens.unregisterCalls)
        assertNull(store.value)
        assertFalse(target.beforeLogout(session).changed)
    }

    @Test
    fun explicitAuthHookUsesNativeOwnerAfterUiReadinessIsRevoked() = runTest {
        val backend = Backend()
        val store = Store()
        val tokens = Tokens()
        val target = coordinator(backend, store, tokens)
        target.reconcile(session, PushGate(true, true))
        assertEquals(
            PushFailure.CROSS_ACCOUNT,
            target.beforeExplicitSignOut("user-a") { false }.failure,
        )
        assertTrue(backend.deletes.isEmpty())
        assertTrue(target.beforeExplicitSignOut("user-a") { true }.changed)
        assertEquals(1, tokens.unregisterCalls)
        assertEquals("user-a", backend.deletes.single().first)
        assertNull(store.value)
    }

    @Test
    fun tokenCannotLeakThroughDiagnosticsAndInvalidValuesFailClosed() {
        val secret = "secret-0123456789-token"
        val token = PushToken.parse(secret)!!
        assertFalse(token.toString().contains(secret))
        assertNull(PushToken.parse("short"))
        assertNull(PushToken.parse("token with whitespace 12345"))
        assertEquals(
            64,
            PushRegistrationContract.stableDocumentId("installation_1234567890").length,
        )
        val fid =
            PushRegistrationContract.create(
                "a123456789012345678901",
                "a123456789012345678901",
                "Pixel",
                "1.0.0",
                "fid",
            )
        assertEquals("fid", fid.registrationType)
        assertFailsWith(PushFailure.INVALID_TOKEN) {
            PushRegistrationContract.create(
                "installation_1234567890",
                "short-fid",
                "Pixel",
                "1.0.0",
                "fid",
            )
        }
    }

    @Test
    fun foregroundAndDataRoutesReuseInboxAndBrowseAllowlists() {
        assertEquals(
            7,
            PushRouting.inboxSync(mapOf("type" to "inboxSync", "unreadCount" to "7")),
        )
        assertNull(PushRouting.inboxSync(mapOf("type" to "inboxSync", "unreadCount" to "-1")))
        assertNull(
            PushRouting.inboxSync(
                mapOf("type" to "inboxSync", "unreadCount" to "7", "routeTargetId" to "x")
            )
        )
        assertEquals(
            "events/event-1",
            at.uac.android.feature.push.PushRouting.route(
                    mapOf(
                        "type" to "eventUpdated",
                        "sourceType" to "event",
                        "actionType" to "openEvent",
                        "routeTargetId" to "event-1",
                        "notificationId" to "notice-1",
                    )
                )
                ?.route,
        )
        assertEquals(
            "profile/inbox",
            at.uac.android.feature.push.PushRouting.route(
                    mapOf("type" to "systemAnnouncement", "actionType" to "none")
                )
                ?.route,
        )
        for (invalid in
            listOf(
                mapOf("type" to "future", "actionType" to "openEvent", "routeTargetId" to "x"),
                mapOf(
                    "type" to "eventUpdated",
                    "actionType" to "openURL",
                    "routeTargetId" to "https://example.invalid",
                ),
                mapOf(
                    "type" to "eventUpdated",
                    "actionType" to "openEvent",
                    "routeTargetId" to "bad/id",
                ),
                mapOf(
                    "type" to "eventUpdated",
                    "actionType" to "openShell",
                    "routeTargetId" to "x",
                ),
            )) assertNull(at.uac.android.feature.push.PushRouting.route(invalid))
    }

    @Test
    fun channelPolicyMatchesServerEnvelopeAndProtectsLockScreen() {
        assertEquals("uac_updates", PushChannelPolicy.ID)
        assertEquals(3, PushChannelPolicy.IMPORTANCE)
        assertTrue(PushChannelPolicy.PRIVATE_LOCK_SCREEN)
        assertTrue(PushChannelPolicy.SOUND_ENABLED)
        assertTrue(PushChannelPolicy.BADGE_ENABLED)
    }

    @Test
    fun exactDeletionCallableUsesOrdinaryBoundedIdempotentProtocol() {
        val request =
            mapOf(
                "userId" to "user-a",
                "identifier" to "token-0123456789-abcdef",
                "registrationType" to "token",
            )
        assertEquals(
            mapOf("data" to request),
            LocalCallableProtocol.request("deleteNotificationPushRegistration", request),
        )
        assertEquals(
            LocalCallableProtocol.MAX_REQUEST_BYTES,
            LocalCallableProtocol.maximumRequestBytes("deleteNotificationPushRegistration"),
        )
        assertEquals(
            60_000,
            LocalCallableProtocol.maximumTimeoutMillis("deleteNotificationPushRegistration"),
        )
        assertFalse(LocalCallableProtocol.nonIdempotent("deleteNotificationPushRegistration"))
    }

    @Test
    fun minimalControllerRoutesOnlyForCurrentConsentedReadySession() = runTest {
        var live: PushSession? = session
        var gate = PushGate(true, true)
        val routes = mutableListOf<PushRouteDecision>()
        val syncs = mutableListOf<Int>()
        val controller =
            PushController(
                coordinator(Backend(), Store(), Tokens()) { live },
                { live },
                { gate },
                routes::add,
                this,
                syncInbox = syncs::add,
            )
        val decision = PushRouteDecision("events/event-1", "notice-1")
        controller.route(decision)
        gate = PushGate(false, true)
        controller.route(decision)
        live = session.copy(verifiedActive = false)
        controller.route(decision)
        assertEquals(listOf(decision), routes)
        gate = PushGate(true, true)
        live = session
        controller.inboxSync(5)
        gate = PushGate(false, true)
        controller.inboxSync(6)
        assertEquals(listOf(5), syncs)
        controller.close()
        assertNull(controller.refresh())
    }

    @Test
    fun coldAndWarmTapQueueRequiresOwnerAndDeduplicatesAfterConsumption() {
        val saved = SavedStateHandle()
        val navigation = PushNavigationViewModel(saved)
        val data =
            mapOf(
                "notificationId" to "notice-1",
                "type" to "eventUpdated",
                "sourceType" to "event",
                "actionType" to "openEvent",
                "routeTargetId" to "event-1",
            )
        assertFalse(navigation.offer(data, null))
        assertTrue(navigation.offer(data, "user-a"))
        val pending = navigation.pending.value!!
        assertEquals("events/event-1", pending.decision.route)
        assertEquals(pending, PushNavigationViewModel(saved).pending.value)
        navigation.consume(pending.revision)
        assertNull(navigation.pending.value)
        assertTrue(navigation.offer(data, "user-a"))
        assertNull(navigation.pending.value)
        assertFalse(navigation.offer(data + ("unexpected" to "value"), "user-a"))
    }

    private fun assertFailsWith(expected: PushFailure, operation: () -> Unit) {
        val error = runCatching(operation).exceptionOrNull()
        assertEquals(expected, (error as? PushException)?.reason)
    }
}
