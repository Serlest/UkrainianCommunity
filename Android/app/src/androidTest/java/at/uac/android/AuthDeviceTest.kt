package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.AuthEmulatorFixtures.actionCode
import at.uac.android.AuthEmulatorFixtures.adminRequest
import at.uac.android.AuthEmulatorFixtures.seedLegalReference
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.startup.StartupAccess
import at.uac.android.feature.startup.startupAccess
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AuthDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"

    @Test
    fun namedAuthConfigurationAndCompleteReferenceLegalRemainIsolated() = runBlocking {
        val first = LocalFirebase.auth(context)
        assertSame(first, LocalFirebase.auth(context))
        assertEquals(LocalEnvironment.PROJECT_ID, first.app.options.projectId)
        assertTrue(FirebaseApp.getApps(context).none { it.name == FirebaseApp.DEFAULT_APP_NAME })
        val legal = bundledReferenceLegal(context)
        assertEquals(3, legal.size)
        assertEquals(AuthRegistration.TERMS_VERSION, legal.first { it.type == "terms" }.version)
        assertEquals(AuthRegistration.PRIVACY_VERSION, legal.first { it.type == "privacy" }.version)
        for (document in legal) for (language in listOf("uk", "de")) {
            assertTrue(document.text(language).length > 1000)
            assertTrue(document.title(language).isNotBlank())
        }
        assertTrue(legal.first { it.type == "terms" }.text("de").contains("iOS"))
        try {
            FirebaseAuthBackend(first).signIn("real@example.com", "NeverSentPassword")
            fail("Real addresses forbidden")
        } catch (error: AuthException) {
            assertEquals(AuthProblem.LOCAL_ONLY, error.problem)
        }
    }

    @Test
    fun realRegistrationVerificationResetAndSessionRestoreOrOfflineFailure() = runBlocking {
        val auth = LocalFirebase.auth(context)
        val database = LocalFirebase.firestore(context)
        val backend = FirebaseAuthBackend(auth)
        val profiles = FirestoreAuthProfiles(database)
        backend.signOut()
        if (!online) {
            val sdkFailure =
                runCatching {
                    auth
                        .signInWithEmailAndPassword(
                            "offline@example.invalid",
                            "NeverSentPassword",
                        )
                        .await()
                }
                    .exceptionOrNull() ?: throw AssertionError("Auth emulator must be stopped")
            val safeType =
                "${sdkFailure.javaClass.name}; code=${(sdkFailure as? com.google.firebase.auth.FirebaseAuthException)?.errorCode}; cause=${sdkFailure.cause?.javaClass?.name}"
            assertEquals(safeType, AuthProblem.NETWORK, authProblem(sdkFailure))
            try {
                withTimeout(15_000) {
                    backend.signIn("offline@example.invalid", "NeverSentPassword")
                }
                fail("Auth emulator must be stopped")
            } catch (error: AuthException) {
                assertEquals(AuthProblem.NETWORK, error.problem)
            }
            assertNull(backend.current)
            return@runBlocking
        }
        seedLegalReference()
        val email = "auth3a-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-Only-Password1"
        val newPassword = "Synthetic-New-Password2"
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(backend, profiles, scope)
        var uid: String? = null
        var secondUid: String? = null
        try {
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertEquals(AuthStage.GUEST, store.state.value.stage)
            withContext(Dispatchers.Main) {
                    store.register(
                        AuthRegistration(
                            email,
                            "Вигаданий користувач",
                            "tirol",
                            "",
                            true,
                            true,
                            true,
                        ),
                        password,
                        password,
                        "uk",
                    )!!
                }
                .join()
            assertEquals(AuthStage.VERIFICATION_PENDING, store.state.value.stage)
            assertFalse(store.state.value.readyForActions)
            uid = backend.current!!.uid
            val profile = database.collection("users").document(uid).get(Source.SERVER).await()
            assertEquals("user", profile.getString("globalRole"))
            assertEquals(AuthRegistration.TERMS_VERSION, profile.getString("acceptedTermsVersion"))
            assertEquals("14+", profile.getString("minimumAgeVersion"))
            assertNotNull(profile.getTimestamp("acceptedTermsAt"))
            assertFalse(profile.contains("role"))
            for (document in profiles.legalDocuments()) {
                val receipt =
                    database.collection("legalAcceptanceLogs")
                        .document("${uid}_${document.type}_${document.version}")
                        .get(Source.SERVER).await()
                assertEquals(uid, receipt.getString("userId"))
                assertEquals(document.type, receipt.getString("documentType"))
                assertEquals(document.version, receipt.getString("version"))
                assertEquals(document.contentHash, receipt.getString("contentHash"))
                assertEquals("android", receipt.getString("acceptedFromPlatform"))
                assertNotNull(receipt.getTimestamp("acceptedAt"))
                assertEquals(profile.getTimestamp("createdAt"), receipt.getTimestamp("acceptedAt"))
            }
            try {
                database
                    .collection("users")
                    .document(uid)
                    .update(
                        mapOf(
                            "displayName" to "Unverified edit",
                            "updatedAt" to FieldValue.serverTimestamp(),
                        )
                    )
                    .await()
                fail("Unverified profile write must fail")
            } catch (error: Exception) {
                assertEquals(AuthProblem.PERMISSION_DENIED, authProblem(error))
            }
            withContext(Dispatchers.Main) { store.checkVerification() }.join()
            assertEquals(AuthStage.VERIFICATION_PENDING, store.state.value.stage)
            val verifyCode = actionCode(email, "VERIFY_EMAIL")
            withContext(Dispatchers.Main) { store.applyVerificationCode(verifyCode)!! }.join()
            assertEquals(AuthStage.AUTHENTICATED, store.state.value.stage)
            assertTrue(store.state.value.readyForActions)
            // A published legal update must revoke the app shell while this
            // account is still signed in. Restore the isolated fixture after it.
            val oldTerms = profiles.legalDocuments().first { it.type == "terms" }
            val newTermsVersion = "2026.11"
            try {
                withContext(Dispatchers.IO) {
                    val root = AuthEmulatorFixtures.documentPath("legalDocuments/terms")
                    adminRequest(
                        8088,
                        "$root/versions/$newTermsVersion",
                        "PATCH",
                        build80LegalFixture(oldTerms.copy(version = newTermsVersion)),
                    )
                    adminRequest(
                        8088,
                        "$root?updateMask.fieldPaths=activeVersion&updateMask.fieldPaths=versionNumber",
                        "PATCH",
                        mapOf(
                            "activeVersion" to newTermsVersion,
                            "versionNumber" to build80VersionNumber(newTermsVersion),
                        ),
                    )
                }
                withTimeout(30_000) {
                    while (store.state.value.gate != AuthGate.LEGAL_REQUIRED) delay(100)
                }
                assertFalse(store.state.value.readyForActions)
                assertEquals(StartupAccess.ACCOUNT, startupAccess(store.state.value))
                assertEquals(
                    newTermsVersion,
                    store.state.value.requiredLegalDocuments().single().version,
                )
            } finally {
                seedLegalReference()
            }
            withTimeout(30_000) {
                while (!store.state.value.readyForActions) delay(100)
            }
            val publicProfile =
                database.collection("publicProfiles").document(uid).get(Source.SERVER).await()
            assertEquals("Вигаданий користувач", publicProfile.getString("displayName"))
            assertFalse(publicProfile.contains("email"))
            assertFalse(publicProfile.contains("globalRole"))
            try {
                database
                    .collection("users")
                    .document("different-synthetic-user")
                    .get(Source.SERVER)
                    .await()
                fail("Foreign profile must fail")
            } catch (error: Exception) {
                assertEquals(AuthProblem.PERMISSION_DENIED, authProblem(error))
            }
            try {
                database.collection("users").document(uid).update("globalRole", "owner").await()
                fail("Role escalation must fail")
            } catch (error: Exception) {
                assertEquals(AuthProblem.PERMISSION_DENIED, authProblem(error))
            }
            val restored = AuthStore(backend, profiles, scope)
            withContext(Dispatchers.Main) { restored.restore() }.join()
            assertTrue(restored.state.value.readyForActions)
            assertEquals(uid, restored.state.value.profile?.uid)
            withContext(Dispatchers.Main) { store.signOut() }.join()
            assertNull(backend.current)
            withContext(Dispatchers.Main) { store.signIn(email, "WrongPassword1")!! }.join()
            assertEquals(AuthStage.GUEST, store.state.value.stage)
            assertEquals(AuthProblem.INVALID_CREDENTIALS, store.state.value.error)
            withContext(Dispatchers.Main) { store.signIn(email, password)!! }.join()
            assertTrue(store.state.value.readyForActions)
            withContext(Dispatchers.Main) { store.sendPasswordReset(email, "de")!! }.join()
            assertEquals(AuthNotice.RESET_SENT, store.state.value.notice)
            val resetCode = actionCode(email, "PASSWORD_RESET")
            withContext(Dispatchers.Main) {
                    store.confirmPasswordReset(resetCode, newPassword, newPassword)!!
                }
                .join()
            assertEquals(AuthStage.GUEST, store.state.value.stage)
            assertNull(backend.current)
            withContext(Dispatchers.Main) { store.signIn(email, password)!! }.join()
            assertEquals(AuthProblem.INVALID_CREDENTIALS, store.state.value.error)
            withContext(Dispatchers.Main) { store.signIn(email, newPassword)!! }.join()
            assertTrue(store.state.value.readyForActions)
            assertEquals(uid, backend.current?.uid)
            // A second account must replace the first profile in the root gate;
            // switching back must restore only the first account's own data.
            withContext(Dispatchers.Main) { store.signOut() }.join()
            val secondEmail = "auth3b-${UUID.randomUUID()}@example.invalid"
            val second = backend.create(secondEmail, password, "Second synthetic account")
            secondUid = second.uid
            val documents = profiles.legalDocuments().associateBy { it.type }
            profiles.create(
                second.uid,
                AuthRegistration(
                    secondEmail,
                    "Second synthetic account",
                    "wien",
                    acceptedTerms = true,
                    acceptedPrivacy = true,
                    minimumAgeConfirmed = true,
                    termsVersion = documents.getValue("terms").version,
                    privacyVersion = documents.getValue("privacy").version,
                    termsContentHash = documents.getValue("terms").contentHash,
                    privacyContentHash = documents.getValue("privacy").contentHash,
                ),
            )
            backend.sendVerification("de")
            backend.verifyEmailCode(actionCode(secondEmail, "VERIFY_EMAIL"))
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertEquals(second.uid, store.state.value.profile?.uid)
            assertEquals(secondEmail, store.state.value.profile?.email)
            assertTrue(store.state.value.readyForActions)
            backend.deleteCreatedUser(second.uid)
            withContext(Dispatchers.Main) { store.signOut() }.join()
            withContext(Dispatchers.Main) { store.signIn(email, newPassword)!! }.join()
            assertEquals(uid, store.state.value.profile?.uid)
            assertEquals(email, store.state.value.profile?.email)
            assertTrue(store.state.value.readyForActions)
        } finally {
            scope.cancel()
            val ownUid = uid
            val otherUid = secondUid
            val keepForProcessProbe =
                InstrumentationRegistry.getArguments().getString("keepAuthSession") == "true"
            if (!keepForProcessProbe) {
                if (backend.current?.uid in listOfNotNull(ownUid, otherUid))
                    backend.deleteCreatedUser(backend.current!!.uid)
                backend.signOut()
                for (accountUid in listOfNotNull(ownUid, otherUid)) {
                    adminRequest(
                        8088,
                        "/v1/projects/${LocalEnvironment.PROJECT_ID}/databases/(default)/documents/users/$accountUid",
                        "DELETE",
                    )
                    adminRequest(
                        8088,
                        "/v1/projects/${LocalEnvironment.PROJECT_ID}/databases/(default)/documents/publicProfiles/$accountUid",
                        "DELETE",
                    )
                    for (document in profiles.legalDocuments())
                        adminRequest(
                            8088,
                            AuthEmulatorFixtures.documentPath(
                                "legalAcceptanceLogs/${accountUid}_${document.type}_${document.version}"
                            ),
                            "DELETE",
                        )
                }
            }
        }
    }
}
