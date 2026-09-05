package at.uac.android

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

/** Pure synthetic policy only. A ready owner here is NOT actual SDK/TOTP proof. */
class PlatformRoleContractTest {
    private val owner = ModerationSession("synthetic-role-owner", 3, "owner", true)
    private val targetId = "synthetic-role-target"
    private val auth = PlatformRoleTargetAuth(targetId, true, false)

    private fun target(role: Any? = "user", account: Any? = "active", block: Any? = "active") =
        PlatformRoleContract.target(
            targetId,
            mapOf("globalRole" to role, "accountStatus" to account, "blockState" to block),
        )

    private fun response(
        action: PlatformRoleAction = PlatformRoleAction.ASSIGN
    ): Map<String, Any?> =
        mapOf(
            "targetUserId" to targetId,
            "previousGlobalRole" to action.previousRole,
            "newGlobalRole" to action.newRole,
            "updatedAt" to "2026-09-03T12:00:00.123Z",
        )

    private fun rejects(expected: PlatformRoleFailure, block: () -> Unit) {
        try {
            block()
            fail("Expected $expected")
        } catch (error: PlatformRoleException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun onlyOwnerWithReadySessionPassesPresentationPolicy() {
        for (role in listOf("owner", "admin", "user", "moderator", "topAdmin", "", "OWNER")) {
            for (ready in listOf(false, true)) {
                val session = owner.copy(role = role, ready = ready)
                if (role == "owner" && ready) PlatformRoleContract.requireSession(session)
                else
                    rejects(PlatformRoleFailure.ACCESS) {
                        PlatformRoleContract.requireSession(session)
                    }
            }
        }
        rejects(PlatformRoleFailure.ACCESS) {
            PlatformRoleContract.requireSession(owner.copy(uid = "bad/id"))
        }
    }

    @Test
    fun selfAndOwnerTargetAreProtectedForBothActions() {
        for (action in PlatformRoleAction.entries) {
            rejects(PlatformRoleFailure.ACCESS) {
                PlatformRoleContract.requireTarget(owner, target("owner"), action, auth)
            }
            rejects(PlatformRoleFailure.ACCESS) {
                PlatformRoleContract.requireTarget(
                    owner,
                    target(action.previousRole).copy(targetId = owner.uid),
                    action,
                    auth,
                )
            }
        }
    }

    @Test
    fun ActorDenialPrecedesTargetOrMetadataValidation() {
        rejects(PlatformRoleFailure.ACCESS) {
            PlatformRoleContract.requireTarget(
                owner.copy(role = "admin"),
                PlatformRoleTarget("bad/id", "bad-role", false),
                PlatformRoleAction.ASSIGN,
                null,
            )
        }
    }

    @Test
    fun assignmentRequiresFreshBoundVerifiedEnabledTargetAuth() {
        for (candidate in
            listOf(
                null,
                auth.copy(targetId = "foreign"),
                auth.copy(emailVerified = false),
                auth.copy(disabled = true),
            )) {
            rejects(PlatformRoleFailure.STALE) {
                PlatformRoleContract.requireTarget(
                    owner,
                    target(),
                    PlatformRoleAction.ASSIGN,
                    candidate,
                )
            }
        }
        PlatformRoleContract.requireTarget(owner, target(), PlatformRoleAction.ASSIGN, auth)
    }

    @Test
    fun assignmentAcceptsOnlyActiveOrWarnedInBothProfileStates() {
        val states =
            listOf(
                null,
                "active",
                "warned",
                "suspendedUntil",
                "bannedPermanent",
                "deactivated",
                "",
                3,
            )
        for (account in states) for (block in states) {
            val candidate = target(account = account, block = block)
            val allowed =
                account in listOf(null, "active", "warned") &&
                    block in listOf(null, "active", "warned")
            assertEquals(allowed, candidate.usableProfile)
            if (allowed)
                PlatformRoleContract.requireTarget(
                    owner,
                    candidate,
                    PlatformRoleAction.ASSIGN,
                    auth,
                )
            else
                rejects(PlatformRoleFailure.STALE) {
                    PlatformRoleContract.requireTarget(
                        owner,
                        candidate,
                        PlatformRoleAction.ASSIGN,
                        auth,
                    )
                }
        }
    }

    @Test
    fun removalNeedsNoTargetAuthEvenForRestrictedDisabledOrMalformedTargetStates() {
        for (state in
            listOf(null, "bannedPermanent", "deactivated", "suspendedUntil", "unknown", 4)) {
            for (candidate in
                listOf(
                    null,
                    auth.copy(disabled = true),
                    auth.copy(emailVerified = false),
                    auth.copy(targetId = "foreign"),
                )) {
                PlatformRoleContract.requireTarget(
                    owner,
                    target("admin", state, state),
                    PlatformRoleAction.REMOVE,
                    candidate,
                )
            }
        }
    }

    @Test
    fun unchangedRoleIsNotAReceiptOrAnAllowedNewDispatch() {
        for (action in PlatformRoleAction.entries) {
            rejects(PlatformRoleFailure.STALE) {
                PlatformRoleContract.requireTarget(owner, target(action.newRole), action, auth)
            }
            rejects(PlatformRoleFailure.UNCONFIRMED) {
                PlatformRoleContract.response(
                    targetId,
                    action,
                    response(action) + ("previousGlobalRole" to action.newRole),
                )
            }
        }
    }

    @Test
    fun legacyUnknownAndAbsentRolesMatchServerNormalization() {
        for (role in
            listOf(
                null,
                "user",
                "moderator",
                "topAdmin",
                "appModerator",
                "unknown",
                "ADMIN",
                5,
                false,
            )) {
            assertEquals("user", target(role).role)
            PlatformRoleContract.requireTarget(owner, target(role), PlatformRoleAction.ASSIGN, auth)
            rejects(PlatformRoleFailure.STALE) {
                PlatformRoleContract.requireTarget(
                    owner,
                    target(role),
                    PlatformRoleAction.REMOVE,
                    auth,
                )
            }
        }
        assertEquals("user", PlatformRoleContract.target(targetId, emptyMap()).role)
    }

    @Test
    fun documentPathNotStoredIdIsTargetAuthority() {
        val value =
            PlatformRoleContract.target(
                targetId,
                mapOf("id" to "foreign-target", "globalRole" to "user"),
            )
        assertEquals(targetId, value.targetId)
        assertEquals(
            targetId,
            PlatformRoleContract.payload(value.targetId, "reason")["targetUserId"],
        )
    }

    @Test
    fun invalidAndMalformedUnicodeIdsFailClosed() {
        for (id in
            listOf(
                "",
                ".",
                "..",
                "a/b",
                " space",
                "space\uFEFF",
                "x\u0000",
                "\uD800",
                "\uDC00",
                "x".repeat(129),
                "__reserved__",
            )) {
            assertFalse(id, PlatformRoleContract.id(id))
            rejects(PlatformRoleFailure.INVALID) { PlatformRoleContract.payload(id, "reason") }
        }
        assertTrue(PlatformRoleContract.id("x".repeat(128)))
        assertTrue(PlatformRoleContract.id("користувач😀"))
    }

    @Test
    fun exactPayloadContainsOnlyTargetAndNonblankNormalizedReason() {
        assertEquals(
            mapOf("targetUserId" to targetId, "reason" to "Причина\n\tGrund 😀"),
            PlatformRoleContract.payload(targetId, "\uFEFF\u2009 Причина\n\tGrund 😀\u00A0"),
        )
        for (reason in
            listOf("", " \n\uFEFF", "a\u0000b", "\uD800", "\uDC00", "x".repeat(65_537))) {
            rejects(PlatformRoleFailure.INVALID) { PlatformRoleContract.payload(targetId, reason) }
        }
    }

    @Test
    fun unicodeWhitespaceMatchesJavascriptTrimNotBroadJavaWhitespace() {
        assertEquals("reason", PlatformRoleContract.normalizeReason("\uFEFF\u2000reason\u2028"))
        // U+200B is not ECMAScript whitespace and must not be silently stripped.
        assertEquals(
            "\u200Breason\u200B",
            PlatformRoleContract.normalizeReason("\u200Breason\u200B"),
        )
    }

    @Test
    fun exactJsonBudgetIncludesEnvelopeUtf8AndEscapes() {
        val overhead =
            "{\"data\":{\"targetUserId\":\"$targetId\",\"reason\":\"\"}}".toByteArray().size
        val budget = LocalCallableProtocol.MAX_REQUEST_BYTES - overhead
        for ((unit, bytes) in listOf("x" to 1, "ж" to 2, "😀" to 4, "\"" to 2, "\\" to 2)) {
            val exact = unit.repeat(budget / bytes) + "x".repeat(budget % bytes)
            assertEquals(exact, PlatformRoleContract.payload(targetId, exact)["reason"])
            rejects(PlatformRoleFailure.INVALID) {
                PlatformRoleContract.payload(targetId, exact + "x")
            }
        }
    }

    @Test
    fun targetMetadataRequiresMatchingIdAndBooleanTypes() {
        val data =
            mapOf("targetUserId" to targetId, "emailVerified" to true, "authDisabled" to false)
        assertEquals(
            auth,
            PlatformRoleContract.targetAuth(targetId, data + ("providerIds" to listOf("password"))),
        )
        for (invalid in
            listOf(
                null,
                emptyMap<String, Any>(),
                data + ("targetUserId" to "foreign"),
                data + ("emailVerified" to "true"),
                data - "authDisabled",
            )) {
            rejects(PlatformRoleFailure.INVALID) {
                PlatformRoleContract.targetAuth(targetId, invalid)
            }
        }
    }

    @Test
    fun bothResponseTransitionsParseWithoutInventingCommitOrAuditIds() {
        for (action in PlatformRoleAction.entries) {
            val parsed = PlatformRoleContract.response(targetId, action, response(action))
            assertEquals(action.previousRole, parsed.previousRole)
            assertEquals(action.newRole, parsed.newRole)
            assertEquals(targetId, parsed.targetId)
            assertEquals(Instant.parse("2026-09-03T12:00:00.123Z"), parsed.wireTime)
        }
    }

    @Test
    fun responsesRejectMissingExtraForeignOwnerAndReversedFields() {
        for (action in PlatformRoleAction.entries) {
            val good = response(action)
            for (key in good.keys) rejects(PlatformRoleFailure.UNCONFIRMED) {
                PlatformRoleContract.response(targetId, action, good - key)
            }
            for (bad in
                listOf(
                    null,
                    false,
                    good + ("auditId" to "invented"),
                    good + ("targetUserId" to "foreign"),
                    good + ("previousGlobalRole" to "owner"),
                    good + ("newGlobalRole" to "owner"),
                    good + ("previousGlobalRole" to "moderator"),
                    response(
                        if (action == PlatformRoleAction.ASSIGN) PlatformRoleAction.REMOVE
                        else PlatformRoleAction.ASSIGN
                    ),
                )) {
                rejects(PlatformRoleFailure.UNCONFIRMED) {
                    PlatformRoleContract.response(targetId, action, bad)
                }
            }
        }
    }

    @Test
    fun wireTimeHasMillisecondPrecisionAndBoundedRange() {
        for (time in
            listOf(
                null,
                3,
                "",
                "y".repeat(41),
                "2026-09-03T12:00:00.123456Z",
                "0000-01-01T00:00:00Z",
                "+10000-01-01T00:00:00Z",
            )) {
            rejects(PlatformRoleFailure.UNCONFIRMED) {
                PlatformRoleContract.response(
                    targetId,
                    PlatformRoleAction.ASSIGN,
                    response() + ("updatedAt" to time),
                )
            }
        }
    }

    @Test
    fun diagnosticStringsDoNotExposeTargetIdsOrContacts() {
        val parsed = PlatformRoleContract.response(targetId, PlatformRoleAction.ASSIGN, response())
        for (item in listOf(target(), auth, parsed)) assertFalse(item.toString().contains(targetId))
    }

    @Test
    fun onlyTwoExactRoleCallsHaveBoundedNonIdempotentTransportAfterSourceIntegration() {
        for (action in PlatformRoleAction.entries) {
            assertEquals(
                "http://10.0.2.2:5008/demo-uac-android/europe-west3/${action.callable}",
                LocalCallableProtocol.endpoint(action.callable),
            )
            assertTrue(LocalCallableProtocol.nonIdempotent(action.callable))
            assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes(action.callable))
            assertEquals(60_000L, LocalCallableProtocol.maximumTimeoutMillis(action.callable))
        }
        assertEquals(
            setOf("assignAppAdmin", "removeAppAdmin"),
            PlatformRoleAction.entries.map { it.callable }.toSet(),
        )
    }
}
