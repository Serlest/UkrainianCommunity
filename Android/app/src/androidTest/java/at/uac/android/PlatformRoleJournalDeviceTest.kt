package at.uac.android

import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.platformrolemanagement.*
import com.google.firebase.FirebaseApp
import java.io.File
import java.io.SyncFailedException
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual files/fsync only on the two root-owned AVDs. No Firebase/account/emulator data writes. */
@RunWith(AndroidJUnit4::class)
class PlatformRoleJournalDeviceTest {
    private val actor = "RAW-NATIVE-JOURNAL-ACTOR"
    private val privateText = "Private synthetic reason and contact must never persist"

    private fun pending(target: String = "synthetic-target", uid: String = actor) =
        PlatformRolePending(
            PlatformRoleRecovery.accountHash(uid),
            PlatformRoleVersion(target, "a".repeat(64), "b".repeat(64), "user"),
            PlatformRoleAction.ASSIGN,
            PlatformRoleRecovery.hash(privateText),
            UUID.randomUUID().toString(),
            PlatformRolePhase.PREPARED,
        )

    private fun acknowledged(dispatched: PlatformRolePending) =
        dispatched.copy(
            phase = PlatformRolePhase.ACKNOWLEDGED,
            receipt =
                PlatformRoleRecovery.receipt(
                    dispatched,
                    mapOf(
                        "targetUserId" to dispatched.version.targetId,
                        "previousGlobalRole" to "user",
                        "newGlobalRole" to "admin",
                        "updatedAt" to "2026-09-03T13:00:00.123Z",
                    ),
                ),
        )

    private fun requireExactAvd() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        CompiledBackend.configuration.requireAndroidPackage(
            instrumentation.targetContext.packageName
        )
        if (isExplicitApi26CompatibilityAvd()) return
        check(
            Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")
        )
        fun property(name: String) =
            ParcelFileDescriptor.AutoCloseInputStream(
                    instrumentation.uiAutomation.executeShellCommand("getprop $name")
                )
                .bufferedReader()
                .use { it.readLine()?.trim().orEmpty() }
        check(
            property("ro.kernel.qemu") == "1" &&
                property("ro.boot.qemu.avd_name") == "UAC_API_37_Play_ARM64"
        )
    }

    private inner class Fixture {
        private val context = InstrumentationRegistry.getInstrumentation().targetContext
        private val token = UUID.randomUUID().toString()
        val directory =
            File(context.noBackupFilesDir, "platform-role-journal-test-$token").canonicalFile
        val base
            get() = File(directory, "pending.bin")

        init {
            requireExactAvd()
            check(!directory.exists() && directory.mkdirs())
        }

        fun store(failSync: Boolean = false) =
            FilePlatformRoleJournal(directory) {
                if (failSync) throw SyncFailedException("Synthetic fsync failure")
                it.fd.sync()
            }

        fun cleanup() {
            requireExactAvd()
            check(
                directory.canonicalFile == directory &&
                    directory.parentFile == context.noBackupFilesDir.canonicalFile &&
                    directory.name == "platform-role-journal-test-$token"
            )
            val failures = mutableListOf<Throwable>()
            directory.listFiles().orEmpty().forEach { file ->
                try {
                    check(
                        file.name in setOf("pending.bin", "pending.bin.new", "pending.bin.bak") &&
                            file.isFile &&
                            file.canonicalFile == file.absoluteFile
                    )
                    check(file.delete())
                } catch (error: Throwable) {
                    failures += error
                }
                try {
                    check(!file.exists())
                } catch (error: Throwable) {
                    failures += error
                }
            }
            if (failures.isEmpty()) check(directory.delete() && !directory.exists())
            else
                throw AssertionError("Exact owned journal cleanup failed").also { failure ->
                    failures.forEach(failure::addSuppressed)
                }
        }
    }

    private suspend fun fixture(action: suspend (Fixture) -> Unit) {
        val disk = Fixture()
        var primary: Throwable? = null
        try {
            action(disk)
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            try {
                disk.cleanup()
            } catch (cleanup: Throwable) {
                if (primary == null) throw cleanup else primary.addSuppressed(cleanup)
            }
        }
    }

    private suspend fun denied(action: suspend () -> Any?) {
        try {
            action()
            fail("Expected native journal rejection")
        } catch (error: PlatformRoleException) {
            assertEquals(PlatformRoleFailure.JOURNAL, error.failure)
        }
    }

    @Test
    fun durablePhasesReopenWithActualReceiptAndNoPrivateText() = runBlocking {
        fixture { disk ->
            val prepared = pending()
            assertEquals(prepared, disk.store().put(actor, prepared))
            val dispatched = prepared.copy(phase = PlatformRolePhase.DISPATCHED)
            disk.store().put(actor, dispatched, prepared)
            val ack = acknowledged(dispatched)
            disk.store().put(actor, ack, dispatched)
            assertEquals(listOf(ack), disk.store().pending(actor))
            assertTrue(disk.store().pending("other-actor").isEmpty())
            val raw = disk.base.readBytes().toString(Charsets.ISO_8859_1)
            assertFalse(raw.contains(actor))
            assertFalse(raw.contains(privateText))
            disk.store().clear(actor, ack)
            assertTrue(disk.store().pending(actor).isEmpty())
        }
    }

    @Test
    fun fsyncFaultCannotPrepareDispatchOrAcknowledgeAndKeepsPreviousBytes() = runBlocking {
        fixture { disk ->
            denied { disk.store(true).put(actor, pending()) }
            assertTrue(disk.store().pending(actor).isEmpty())
        }
        fixture { disk ->
            val prepared = pending()
            disk.store().put(actor, prepared)
            val bytes = disk.base.readBytes()
            val dispatched = prepared.copy(phase = PlatformRolePhase.DISPATCHED)
            denied { disk.store(true).put(actor, dispatched, prepared) }
            assertArrayEquals(bytes, disk.base.readBytes())
            assertEquals(listOf(prepared), disk.store().pending(actor))
            disk.store().put(actor, dispatched, prepared)
            val sentBytes = disk.base.readBytes()
            denied { disk.store(true).put(actor, acknowledged(dispatched), dispatched) }
            assertArrayEquals(sentBytes, disk.base.readBytes())
            assertEquals(listOf(dispatched), disk.store().pending(actor))
        }
    }

    @Test
    fun corruptOversizedTruncatedAndForeignBoundFilesNeverBecomeEmpty() = runBlocking {
        val encoded = PlatformRoleJournalCodec.encode(listOf(pending()))
        for (bytes in
            listOf(
                byteArrayOf(1, 2, 3),
                ByteArray(32_769),
                encoded.copyOf(10),
                encoded + 0,
                encoded.copyOf().also {
                    it[9] = if (it[9] == 'a'.code.toByte()) 'b'.code.toByte() else 'a'.code.toByte()
                },
            )) {
            fixture { disk ->
                disk.base.writeBytes(bytes)
                denied { disk.store().pending(actor) }
                denied { disk.store().put(actor, pending()) }
                denied { disk.store().clear(actor, pending()) }
                assertArrayEquals(bytes, disk.base.readBytes())
            }
        }
    }

    @Test
    fun orphanNewAndBakFailClosedWithAndWithoutValidBase() = runBlocking {
        for (suffix in listOf(".new", ".bak")) for (withBase in listOf(false, true)) {
            fixture { disk ->
                val prepared = pending()
                if (withBase) disk.store().put(actor, prepared)
                val original = if (withBase) disk.base.readBytes() else null
                val orphan = File(disk.base.path + suffix)
                val bytes =
                    PlatformRoleJournalCodec.encode(
                        listOf(prepared.copy(phase = PlatformRolePhase.DISPATCHED))
                    )
                orphan.writeBytes(bytes)
                denied { disk.store().pending(actor) }
                denied { disk.store().put(actor, pending()) }
                denied { disk.store().clear(actor, prepared) }
                assertArrayEquals(bytes, orphan.readBytes())
                if (original == null) assertFalse(disk.base.exists())
                else assertArrayEquals(original, disk.base.readBytes())
            }
        }
    }

    @Test
    fun exactCasWrongActorBackendAndWrongDeletionCannotAlterPending() = runBlocking {
        fixture { disk ->
            val prepared = pending()
            disk.store().put(actor, prepared)
            val bytes = disk.base.readBytes()
            denied {
                disk
                    .store()
                    .put(
                        "other-actor",
                        prepared.copy(phase = PlatformRolePhase.DISPATCHED),
                        prepared,
                    )
            }
            denied { disk.store().clear("other-actor", prepared) }
            denied { disk.store().put(actor, prepared.copy(backend = "uac-android-test-20260903")) }
            denied { disk.store().put(actor, prepared.copy(phase = PlatformRolePhase.DISPATCHED)) }
            denied {
                disk.store().clear(actor, prepared.copy(operationId = UUID.randomUUID().toString()))
            }
            denied {
                disk
                    .store()
                    .put(
                        actor,
                        prepared.copy(
                            phase = PlatformRolePhase.DISPATCHED,
                            reasonHash = "f".repeat(64),
                        ),
                        prepared,
                    )
            }
            denied {
                disk
                    .store()
                    .put(
                        actor,
                        prepared.copy(phase = PlatformRolePhase.DISPATCHED),
                        prepared.copy(operationId = UUID.randomUUID().toString()),
                    )
            }
            assertArrayEquals(bytes, disk.base.readBytes())
            assertEquals(listOf(prepared), disk.store().pending(actor))
        }
    }

    @Test
    fun globalCapacityAndDuplicateOperationPreserveBothAccounts() = runBlocking {
        fixture { disk ->
            repeat(16) { index ->
                val uid = if (index % 2 == 0) actor else "other-actor"
                disk.store().put(uid, pending("target-$index", uid))
            }
            val bytes = disk.base.readBytes()
            denied { disk.store().put(actor, pending("overflow")) }
            assertArrayEquals(bytes, disk.base.readBytes())
            assertEquals(8, disk.store().pending(actor).size)
            assertEquals(8, disk.store().pending("other-actor").size)
        }
        fixture { disk ->
            val first = pending()
            disk.store().put(actor, first)
            val bytes = disk.base.readBytes()
            denied {
                disk
                    .store()
                    .put(
                        "other-actor",
                        pending("another", "other-actor").copy(operationId = first.operationId),
                    )
            }
            assertArrayEquals(bytes, disk.base.readBytes())
        }
    }

    @Test
    fun independentInstancesSerializeTheSameTargetCompareAndSet() = runBlocking {
        fixture { disk ->
            val entries = listOf(pending(), pending())
            val outcomes = coroutineScope {
                entries
                    .map { entry ->
                        async(Dispatchers.IO) { runCatching { disk.store().put(actor, entry) } }
                    }
                    .awaitAll()
            }
            assertEquals(1, outcomes.count { it.isSuccess })
            assertEquals(1, outcomes.count { it.exceptionOrNull() is PlatformRoleException })
            val winner = outcomes.single { it.isSuccess }.getOrThrow()
            assertEquals(listOf(winner), disk.store().pending(actor))
        }
    }

    @Test
    fun fileAndCodecOperationsNeverInitializeFirebase() = runBlocking {
        requireExactAvd()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val before = FirebaseApp.getApps(context).toList()
        fixture { disk ->
            val entry = pending()
            disk.store().put(actor, entry)
            disk.store().clear(actor, entry)
        }
        val after = FirebaseApp.getApps(context)
        assertEquals(before.size, after.size)
        before.forEach { previous -> assertTrue(after.any { it === previous }) }
    }
}
