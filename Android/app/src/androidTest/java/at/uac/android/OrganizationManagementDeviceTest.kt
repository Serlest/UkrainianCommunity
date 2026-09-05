package at.uac.android

import android.graphics.Bitmap
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.*
import at.uac.android.feature.auth.*
import at.uac.android.feature.organization.*
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Synthetic AVD only. No injected token claims, real TOTP claim, remote endpoint, or backend
 * contract changes.
 */
@RunWith(AndroidJUnit4::class)
class OrganizationManagementDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private var phase = "setup"
    private val password = "Synthetic-org4b-test-only!"

    @Test
    fun localManagementGuestAndEndpointGuardRemainClosed() = runBlocking {
        val source = localOrganizationManagementSource(context)
        val gate =
            object : OrganizationMutationGate {
                override suspend fun <T> withSession(
                    session: OrganizationSession,
                    operation: suspend () -> T,
                ): T = error("Guest reached write gate")
            }
        expect(OrganizationManagementFailure.SIGN_IN) {
            OrganizationManagementRepository(source, { null }, gate).load("synthetic-organization")
        }
        try {
            LocalCallableProtocol.endpoint(
                "assignOrganizationAdmin",
                project = "uac-android-test-20260903",
            )
            fail("Cloud rejected")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun approvedInfoRolesCandidatesAndAccountNegativesUseActualLocalContracts() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        if (args.getString("expectFunctions") != "true") return@runBlocking
        check(args.getString("expectEmulator") == "true")
        check(Build.HARDWARE in setOf("ranchu", "goldfish") && Build.MODEL.startsWith("sdk_gphone"))
        check(context.packageName == "at.uac.android.local")
        LocalEnvironment.requireSafe()
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val functions = LocalFunctions.instance(context)
        val source = localOrganizationManagementSource(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val repository =
            OrganizationManagementRepository(
                source,
                { store.state.value.organizationScope() },
                AuthOrganizationMutationGate(store),
            )
        val prefix = "org4b-${UUID.randomUUID()}"
        val organizationId = "$prefix-org"
        val fixture = OrganizationManagementFixtures(prefix, organizationId)
        var failure: Throwable? = null
        data class Account(val uid: String, val email: String)
        suspend fun account(label: String, verified: Boolean = true): Account {
            auth.signOut()
            val email = "$prefix-$label@example.invalid"
            val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
            fixture.uids += user.uid
            db.document("users/${user.uid}")
                .set(
                    registeredProfileFields(
                        user.uid,
                        AuthRegistration(
                            email,
                            "Synthetic $label",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            if (verified) {
                user.sendEmailVerification().await()
                auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
                user.reload().await()
                user.getIdToken(true).await()
                assertTrue(user.isEmailVerified)
            }
            fixture.seed(
                "publicProfiles/${user.uid}",
                mapOf(
                    "id" to user.uid,
                    "displayName" to "Public $label",
                    "city" to "Wien",
                    "updatedAt" to Instant.now(),
                ),
            )
            return Account(user.uid, email)
        }
        suspend fun signIn(account: Account) {
            withContext(Dispatchers.Main) { store.signOut() }.join()
            withContext(Dispatchers.Main) { store.signIn(account.email, password)!! }.join()
            assertTrue(
                "$phase: actor must have actual ready session",
                store.state.value.readyForActions,
            )
            assertEquals(account.uid, auth.currentUser?.uid)
        }
        suspend fun direct(name: String, targetId: String) =
            functions
                .getHttpsCallable(name)
                .call(mapOf("organizationId" to organizationId, "targetUserId" to targetId))
                .await()
                .data
        try {
            AuthEmulatorFixtures.seedLegalReference()
            phase = "create synthetic identities"
            val owner = account("owner", verified = false)
            phase = "unverified real token denied before role handler"
            expect(OrganizationManagementFailure.DENIED) {
                direct("assignOrganizationAdmin", "$prefix-missing")
            }
            auth.currentUser!!.sendEmailVerification().await()
            auth
                .applyActionCode(AuthEmulatorFixtures.actionCode(owner.email, "VERIFY_EMAIL"))
                .await()
            auth.currentUser!!.reload().await()
            auth.currentUser!!.getIdToken(true).await()
            val target = account("target")
            val unverified = account("unverified", verified = false)
            val disabled = account("disabled")
            val restricted = account("restricted")
            fixture.authAccount(disabled.uid, "update", mapOf("disableUser" to true))
            fixture.patch(
                "users/${restricted.uid}",
                mapOf("accountStatus" to "suspendedUntil", "blockState" to "suspendedUntil"),
            )
            signIn(owner)
            val actor = store.state.value.organizationScope()!!
            val basic =
                OrganizationDraft(
                    organizationId,
                    "Synthetic approved community",
                    "A complete approved local organization",
                    region = "wien",
                    city = "Wien",
                )
            val now = Instant.now()
            fixture.seed(
                "organizations/$organizationId",
                OrganizationContract.create(basic, actor, now) +
                    mapOf(
                        "moderationStatus" to "approved",
                        "ownerId" to owner.uid,
                        "likeCount" to 7L,
                        "subscriberCount" to 4L,
                        "socialLinks" to mapOf("custom" to "https://example.invalid"),
                        "coverURL" to "https://example.invalid/cover",
                    ),
            )
            for ((index, candidate) in
                listOf(target, unverified, disabled, restricted).withIndex()) {
                fixture.seed(
                    "likes/organization_follow_${organizationId}_${candidate.uid}",
                    mapOf(
                        "id" to "organization_follow_${organizationId}_${candidate.uid}",
                        "userId" to candidate.uid,
                        "subscribedOrganizationId" to organizationId,
                        "createdAt" to now.minusSeconds(index.toLong()),
                    ),
                )
            }
            phase = "fresh approved authority and public-only subscribers"
            assertNull(source.organization("$prefix-missing", actor))
            val loaded = repository.load(organizationId)
            assertEquals(OrganizationAuthority.OWNER, loaded.organization.authority)
            assertEquals(5, loaded.members.size)
            assertEquals(
                listOf(target.uid, unverified.uid, disabled.uid, restricted.uid),
                loaded.subscriberIds,
            )
            assertEquals(
                "Public target",
                loaded.members.single { it.profile.id == target.uid }.profile.displayName,
            )
            expect(OrganizationManagementFailure.DENIED) {
                db.document("users/${target.uid}").get(Source.SERVER).await()
            }
            phase = "owner approved information whitelist and timestamp read-back"
            val draft =
                OrganizationManagementContract.draft(loaded.organization)
                    .copy(
                        basics =
                            OrganizationManagementContract.draft(loaded.organization)
                                .basics
                                .copy(
                                    name = "Updated approved community",
                                    germanName = "Aktualisierte Gemeinschaft",
                                ),
                        category = "support",
                        foundedYear = "2020",
                        foundedMonth = "4",
                        languages = "Ukrainisch, Deutsch",
                        mission = "Synthetic public mission",
                        directory =
                            OrganizationDirectoryDraft(
                                services = "Advice\nMeetups",
                                regularHours =
                                    mapOf("monday" to "09:00-17:00", "sunday" to "closed"),
                                offerTitle = "Synthetic local offer",
                                offerUntil = "2026-10-01T21:59:59.999999999Z",
                            ),
                    )
            val updated = repository.save(loaded.organization, draft, null).organization
            assertEquals("Updated approved community", updated.name)
            assertEquals(7L, updated.fields["likeCount"])
            assertEquals(4L, updated.fields["subscriberCount"])
            assertEquals(loaded.organization.createdAt, updated.createdAt)
            assertEquals(owner.uid, updated.fields["ownerId"])
            assertEquals("https://example.invalid/cover", updated.fields["coverURL"])
            assertEquals(
                mapOf("custom" to "https://example.invalid"),
                updated.fields["socialLinks"],
            )
            assertEquals(
                Instant.parse("2026-10-01T21:59:59.999999Z"),
                (updated.fields["directoryProfile"] as Map<*, *>)["currentOfferValidUntil"],
            )
            phase = "direct identity roles counters moderation and creation-time injection denied"
            for ((key, value) in
                mapOf(
                    "ownerId" to target.uid,
                    "adminIds" to listOf(target.uid),
                    "likeCount" to 100L,
                    "moderationStatus" to "pendingReview",
                    "createdAt" to Timestamp.now(),
                )) expect(OrganizationManagementFailure.DENIED) {
                db.document("organizations/$organizationId").update(key, value).await()
            }
            phase = "owner logo exact canonical read-back"
            val bitmap =
                Bitmap.createBitmap(12, 8, Bitmap.Config.ARGB_8888).apply {
                    eraseColor(android.graphics.Color.BLUE)
                }
            val jpeg =
                try {
                    ByteArrayOutputStream().use {
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it)
                        it.toByteArray()
                    }
                } finally {
                    bitmap.recycle()
                }
            val withLogo = repository.save(updated, draft, jpeg)
            assertFalse(withLogo.logoIncomplete)
            assertTrue(
                LocalStorage.urlMatches(
                    withLogo.organization.fields["logoURL"] as String,
                    "organizations/$organizationId/logo.jpg",
                )
            )
            assertArrayEquals(
                jpeg,
                LocalStorage.instance(context)
                    .reference
                    .child("organizations/$organizationId/logo.jpg")
                    .getBytes(3_000_000)
                    .await(),
            )
            phase = "assign admin actual callable and canonical arrays"
            val assignment =
                OrganizationRoleIntent(
                    target.uid,
                    OrganizationTeamAction.ADMIN,
                    OrganizationTeamRole.MEMBER,
                )
            val assigned = repository.apply(withLogo.organization, assignment)
            assertEquals(listOf(target.uid), assigned.fields["adminIds"])
            assertEquals(emptyList<String>(), assigned.fields["moderatorIds"])
            val auditCount = fixture.roleAuditIds(owner.uid).size
            assertEquals(1, auditCount)
            repository.apply(withLogo.organization, assignment)
            assertEquals(
                "Recovered desired role cannot append duplicate audit",
                auditCount,
                fixture.roleAuditIds(owner.uid).size,
            )
            phase = "organization admin may edit but cannot manage team"
            signIn(target)
            val adminRecord = repository.load(organizationId).organization
            assertEquals(OrganizationAuthority.ADMIN, adminRecord.authority)
            val adminDraft =
                OrganizationManagementContract.draft(adminRecord)
                    .copy(mission = "Information edited by organization admin")
            val adminSaved = repository.save(adminRecord, adminDraft, null).organization
            assertEquals(
                "Information edited by organization admin",
                adminSaved.fields["missionStatement"],
            )
            // The handler validates target eligibility before actor organization authority.
            // This actual verified, active admin is eligible; only the actor-role gate may deny.
            expect(OrganizationManagementFailure.DENIED) {
                direct("assignOrganizationModerator", target.uid)
            }
            val afterDeniedAssignment = repository.load(organizationId).organization
            assertEquals(listOf(target.uid), afterDeniedAssignment.fields["adminIds"])
            assertEquals(emptyList<String>(), afterDeniedAssignment.fields["moderatorIds"])
            phase = "canonical role revocation closes old information draft"
            fixture.patch(
                "organizations/$organizationId",
                mapOf(
                    "adminIds" to emptyList<String>(),
                    "moderatorIds" to listOf(target.uid),
                    "updatedAt" to Instant.now(),
                ),
            )
            expect(OrganizationManagementFailure.DENIED) {
                repository.save(adminSaved, adminDraft, null)
            }
            expect(OrganizationManagementFailure.DENIED) {
                db.document("organizations/$organizationId")
                    .update("name", "Moderator must not edit")
                    .await()
            }
            val moderator = repository.load(organizationId).organization
            assertEquals(OrganizationAuthority.MODERATOR, moderator.authority)
            expect(OrganizationManagementFailure.DENIED) {
                direct("removeOrganizationAdmin", target.uid)
            }
            phase = "owner promotion demotion and full removal"
            signIn(owner)
            var current = repository.load(organizationId).organization
            current =
                repository.apply(
                    current,
                    assignment.copy(previousRole = OrganizationTeamRole.MODERATOR),
                )
            current =
                repository.apply(
                    current,
                    OrganizationRoleIntent(
                        target.uid,
                        OrganizationTeamAction.MODERATOR,
                        OrganizationTeamRole.ADMIN,
                    ),
                )
            assertEquals(emptyList<String>(), current.fields["adminIds"])
            assertEquals(listOf(target.uid), current.fields["moderatorIds"])
            current =
                repository.apply(
                    current,
                    OrganizationRoleIntent(
                        target.uid,
                        OrganizationTeamAction.REMOVE,
                        OrganizationTeamRole.MODERATOR,
                    ),
                )
            assertEquals(emptyList<String>(), current.fields["adminIds"])
            assertEquals(emptyList<String>(), current.fields["moderatorIds"])
            phase = "missing unverified disabled and restricted target failures"
            for (uid in
                listOf("$prefix-missing", unverified.uid, disabled.uid, restricted.uid)) expect(
                OrganizationManagementFailure.TARGET_UNAVAILABLE
            ) {
                direct("assignOrganizationAdmin", uid)
            }
            phase = "missing target profile may be cleaned from both role arrays"
            fixture.delete("users/${target.uid}")
            fixture.delete("publicProfiles/${target.uid}")
            fixture.patch(
                "organizations/$organizationId",
                mapOf(
                    "adminIds" to listOf(target.uid),
                    "moderatorIds" to listOf(target.uid),
                    "updatedAt" to Instant.now(),
                ),
            )
            current = repository.load(organizationId).organization
            val missingMember =
                repository.load(organizationId).members.single { it.profile.id == target.uid }
            assertNull(missingMember.profile.displayName)
            current =
                repository.apply(
                    current,
                    OrganizationRoleIntent(
                        target.uid,
                        OrganizationTeamAction.REMOVE,
                        OrganizationTeamRole.ADMIN,
                    ),
                )
            assertEquals(emptyList<String>(), current.fields["adminIds"])
            assertEquals(emptyList<String>(), current.fields["moderatorIds"])
            phase = "organization owner removal and platform-only transfer denied"
            expect(OrganizationManagementFailure.DENIED) {
                direct("removeOrganizationAdmin", owner.uid)
            }
            expect(OrganizationManagementFailure.DENIED) {
                direct("transferOrganizationOwnership", owner.uid)
            }
            phase = "real owner privilege without genuine TOTP remains closed"
            fixture.patch(
                "users/${owner.uid}",
                mapOf(
                    "globalRole" to "owner",
                    "requiresMultiFactorAuth" to true,
                    "multiFactorAuthMethod" to "totp",
                ),
            )
            withContext(Dispatchers.Main) { store.refresh() }.join()
            assertFalse(store.state.value.readyForActions)
            val denied = runCatching {
                direct("transferOrganizationOwnership", restricted.uid)
            }
                .exceptionOrNull()
            assertEquals(
                LocalCallableFailure.FAILED_PRECONDITION,
                (denied as? LocalCallableException)?.code,
            )
        } catch (error: Throwable) {
            val reported = AssertionError("Organization management phase=$phase", error)
            failure = reported
            throw reported
        } finally {
            scope.cancel()
            auth.signOut()
            fixture.cleanup(failure)
        }
    }

    private suspend fun expect(
        expected: OrganizationManagementFailure,
        operation: suspend () -> Unit,
    ) {
        try {
            operation()
            fail("$phase: expected $expected")
        } catch (error: Exception) {
            if (organizationManagementFailure(error) != expected)
                throw AssertionError(
                    "$phase: expected $expected, actual=${organizationManagementFailure(error)}",
                    error,
                )
        }
    }
}
