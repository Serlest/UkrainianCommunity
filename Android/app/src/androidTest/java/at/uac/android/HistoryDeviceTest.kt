package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.history.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryDeviceTest {
    private val context
        get() = AccountDeletionFixtures.context

    private suspend fun denied(action: suspend () -> Any?) {
        try {
            action()
            fail("Unchanged Rules must deny this operation")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }

    private suspend fun failure(reason: HistoryFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $reason")
        } catch (error: HistoryException) {
            assertEquals(reason, error.failure)
        }
    }

    @Test
    fun realRecentAndImmutableMarkerTransactionActivityReceiptAndBoundedDeleteOrGuard() =
        runBlocking {
            AccountDeletionFixtures.requireLocalAvd()
            if (!AccountDeletionFixtures.online()) {
                failure(HistoryFailure.SIGN_IN) {
                    HistoryRepository(
                            localHistorySource(context),
                            { null },
                            { true },
                            DirectHistoryMutationGate,
                        )
                        .page(HistorySection.RECENT)
                }
                return@runBlocking
            }
            AuthEmulatorFixtures.seedLegalReference()
            val user = AccountDeletionFixtures.create("deletion-history")
            val fixture = HistoryDeviceFixtures(user.uid)
            val db = LocalFirebase.firestore(context)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            var primary: Throwable? = null
            try {
                fixture.seedTargets()
                val auth =
                    AuthStore(
                        FirebaseAuthBackend(LocalFirebase.auth(context)),
                        FirestoreAuthProfiles(db),
                        scope,
                    )
                withContext(Dispatchers.Main) { auth.restore() }.join()
                val session = auth.state.value.historyScope()!!
                assertTrue(session.ready)
                var visible = true
                val repository =
                    HistoryRepository(
                        localHistorySource(context),
                        { auth.state.value.historyScope() },
                        { visible },
                        AuthHistoryMutationGate(auth),
                    )
                for (target in fixture.targets) {
                    val intent = HistoryContract.write(session, target, null, "de")
                    fixture.path(intent.section, intent.id)
                    if (target.type != HistoryType.ORGANIZATION) fixture.marker(target)
                    val first = repository.write(intent) { true }
                    assertEquals(target.type != HistoryType.ORGANIZATION, first.markerCreated)
                    assertTrue(first.record.title.startsWith("Synthetic history"))
                    val markerBefore =
                        if (target.type != HistoryType.ORGANIZATION)
                            db.document(fixture.marker(target))
                                .get(Source.SERVER)
                                .await()
                                .getTimestamp("createdAt")
                        else null
                    val second = repository.write(intent) { true }
                    assertFalse(second.markerCreated)
                    assertEquals(
                        7L,
                        db.document(target.path).get(Source.SERVER).await().getLong("viewCount"),
                    )
                    if (markerBefore != null) {
                        val ref = db.document(fixture.marker(target))
                        assertEquals(
                            markerBefore,
                            ref.get(Source.SERVER).await().getTimestamp("createdAt"),
                        )
                        denied { ref.update("createdAt", FieldValue.serverTimestamp()).await() }
                        denied { ref.delete().await() }
                    }
                }
                val activity =
                    HistoryContract.write(
                        session,
                        fixture.targets.first(),
                        HistoryAction.SAVE_NEWS,
                        "uk",
                    )
                fixture.path(activity.section, activity.id)
                val first = repository.write(activity) { true }
                val replay = repository.write(activity) { true }
                assertEquals(first.record, replay.record)
                denied {
                    db.document(fixture.path(activity.section, activity.id))
                        .update("title", "Tamper")
                        .await()
                }
                denied {
                    db.document(
                            "users/synthetic-other/recentViews/${fixture.targets.first().recentId}"
                        )
                        .get(Source.SERVER)
                        .await()
                }
                val page = repository.page(HistorySection.RECENT)
                assertEquals(3, page.entries.size)
                assertTrue(page.entries.all { it.content != null })
                val organization = fixture.targets.single { it.type == HistoryType.ORGANIZATION }
                fixture.patch(organization.path, mapOf("moderationStatus" to "draft"), merge = true)
                val mixed = repository.page(HistorySection.RECENT)
                assertEquals(3, mixed.entries.size)
                assertEquals(2, mixed.entries.count { it.content != null })
                assertNull(mixed.entries.single { it.record.target == organization }.content)
                fixture.patch(
                    organization.path,
                    mapOf("moderationStatus" to "approved"),
                    merge = true,
                )
                visible = false
                assertTrue(
                    repository.page(HistorySection.RECENT).entries.all { it.content == null }
                )
                visible = true
                val old = page.entries.first().record
                fixture.patch(
                    fixture.path(HistorySection.RECENT, old.id),
                    mapOf("viewedAt" to old.at.plusSeconds(1)),
                    merge = true,
                )
                failure(HistoryFailure.CONFLICT) {
                    repository.delete(HistoryDelete(session, HistorySection.RECENT, listOf(old)))
                }
                assertNotNull(fixture.read(fixture.path(HistorySection.RECENT, old.id)))
                val fresh = repository.page(HistorySection.RECENT)
                repository.delete(
                    HistoryDelete(session, HistorySection.RECENT, fresh.entries.map { it.record })
                )
                assertTrue(repository.page(HistorySection.RECENT).entries.isEmpty())
                assertNotNull(
                    db.document(fixture.marker(fixture.targets.first()))
                        .get(Source.SERVER)
                        .await()
                        .getTimestamp("createdAt")
                )
                assertEquals(HistoryReconciliation.PRESENT, repository.reconcile(activity))
                repository.delete(
                    HistoryDelete(session, HistorySection.ACTIVITY, listOf(first.record))
                )
                assertEquals(HistoryReconciliation.ABSENT, repository.reconcile(activity))
            } catch (error: Throwable) {
                primary = error
                throw error
            } finally {
                scope.cancel()
                cleanup(fixture, user, primary)
            }
        }

    @Test
    fun realWindowCapsCancellationOfflineAndAccountRulesOrGuard() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        if (!AccountDeletionFixtures.online()) {
            failure(HistoryFailure.NOT_READY) {
                HistoryRepository(
                        localHistorySource(context),
                        { HistorySession("synthetic", 1, false) },
                        { true },
                        DirectHistoryMutationGate,
                    )
                    .page(HistorySection.ACTIVITY)
            }
            return@runBlocking
        }
        AuthEmulatorFixtures.seedLegalReference()
        val user = AccountDeletionFixtures.create("deletion-history-gates")
        val fixture = HistoryDeviceFixtures(user.uid)
        val db = LocalFirebase.firestore(context)
        val source = localHistorySource(context)
        val session = HistorySession(user.uid, 1, true)
        val repository = HistoryRepository(source, { session }, { true }, DirectHistoryMutationGate)
        var primary: Throwable? = null
        try {
            fixture.seedTargets()
            fixture.seedWindow(HistorySection.RECENT, 31)
            fixture.seedWindow(HistorySection.ACTIVITY, 101)
            val first = repository.page(HistorySection.RECENT)
            val last = repository.page(HistorySection.RECENT, first.next)
            assertEquals(30, first.entries.size + last.entries.size)
            assertTrue(last.capped)
            assertNull(last.next)
            assertTrue(
                "Deleted targets remain generic records, not private snapshot titles",
                (first.entries + last.entries).all { it.content == null },
            )
            var cursor: HistoryCursor? = null
            repeat(4) { index ->
                val page = repository.page(HistorySection.ACTIVITY, cursor)
                cursor = page.next
                assertEquals(25, page.entries.size)
                if (index == 3) {
                    assertTrue(page.capped)
                    assertNull(cursor)
                }
            }
            val event = fixture.targets.single { it.type == HistoryType.EVENT }
            fixture.patch(event.path, mapOf("cancellationState" to "cancelled"), merge = true)
            val intent = HistoryContract.write(session, event, null, "de")
            fixture.path(HistorySection.RECENT, intent.id)
            fixture.marker(event)
            failure(HistoryFailure.DENIED) { source.write(intent, { true }, { true }) }
            assertNull(fixture.read(fixture.marker(event)))
            assertNull(fixture.read(fixture.path(HistorySection.RECENT, intent.id)))
            db.disableNetwork().await()
            try {
                failure(HistoryFailure.OFFLINE) { repository.page(HistorySection.RECENT) }
            } finally {
                db.enableNetwork().await()
            }
            fixture.patch(
                "users/${user.uid}",
                mapOf("accountStatus" to "deactivated", "blockState" to "deactivated"),
                merge = true,
            )
            val target = fixture.targets.first()
            val path = fixture.path(HistorySection.RECENT, target.recentId)
            // Intentionally skip the client ready gate only in this negative test; actual Rules
            // independently reject the write.
            denied {
                db.document(path)
                    .set(
                        HistoryContract.fields(
                            target,
                            null,
                            "Synthetic",
                            null,
                            null,
                            target.recentId,
                            FieldValue.serverTimestamp(),
                        )
                    )
                    .await()
            }
            LocalFirebase.auth(context).signOut()
            try {
                source.page(session, HistorySection.RECENT, null, 15)
                fail("Old identity must not read")
            } catch (_: CancellationException) {}
            LocalFirebase.auth(context)
                .signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                .await()
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            var cleanupFailure = primary
            try {
                db.enableNetwork().await()
            } catch (error: Throwable) {
                if (cleanupFailure != null) cleanupFailure.addSuppressed(error)
                else cleanupFailure = error
            }
            cleanup(fixture, user, cleanupFailure)
            if (primary == null && cleanupFailure != null) throw cleanupFailure
        }
    }

    private suspend fun cleanup(
        fixture: HistoryDeviceFixtures,
        user: AccountDeletionFixtures.User,
        primary: Throwable?,
    ) {
        var failure = primary
        try {
            fixture.cleanup(primary)
        } catch (error: Throwable) {
            if (failure == null) failure = error else failure.addSuppressed(error)
        }
        try {
            val auth = LocalFirebase.auth(context)
            if (auth.currentUser == null)
                auth
                    .signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                    .await()
            AccountDeletionFixtures.clean(user)
        } catch (error: Throwable) {
            if (failure == null) failure = error else failure.addSuppressed(error)
        }
        if (primary == null && failure != null) throw failure
    }
}
