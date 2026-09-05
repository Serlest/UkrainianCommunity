package at.uac.android

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalEnvironment
import java.io.EOFException
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Connection
import okhttp3.ConnectionPool
import okhttp3.EventListener
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Read-only transport experiment: unknown emulator route, no callable, no Auth headers, no database
 * mutation.
 */
@RunWith(AndroidJUnit4::class)
class LocalCallableConnectionDeviceTest {
    private class Connections : EventListener() {
        val connects = AtomicInteger()
        val used = mutableListOf<Connection>()

        override fun connectStart(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy) {
            connects.incrementAndGet()
        }

        override fun connectionAcquired(call: Call, connection: Connection) {
            synchronized(used) { used += connection }
        }
    }

    private fun client(events: Connections, noIdle: Boolean): OkHttpClient =
        OkHttpClient.Builder()
            .proxy(Proxy.NO_PROXY)
            .retryOnConnectionFailure(false)
            .followRedirects(false)
            .followSslRedirects(false)
            .connectTimeout(10, TimeUnit.SECONDS)
            .callTimeout(12, TimeUnit.SECONDS)
            .eventListener(events)
            .apply { if (noIdle) connectionPool(ConnectionPool(0, 1, TimeUnit.SECONDS)) }
            .build()

    private suspend fun probe(client: OkHttpClient): String? =
        withContext(Dispatchers.IO) {
            val body =
                object : RequestBody() {
                    override fun contentType() = "application/json; charset=utf-8".toMediaType()

                    override fun contentLength() = 2L

                    override fun isOneShot() = true

                    override fun writeTo(sink: BufferedSink) {
                        sink.writeUtf8("{}")
                    }
                }
            val request =
                Request.Builder()
                    .url("http://${LocalEnvironment.HOST}:5008/__uac_readonly_keepalive_probe__")
                    .post(body)
                    .build()
            // newBuilder intentionally mirrors LocalCallableClient's per-timeout client; its pool
            // is shared.
            client
                .newBuilder()
                .readTimeout(12, TimeUnit.SECONDS)
                .build()
                .newCall(request)
                .execute()
                .use {
                    assertEquals(404, it.code)
                    val header = it.header("Keep-Alive")
                    it.body!!.bytes()
                    header
                }
        }

    @Test
    fun reproduceStaleIdleSocketWithoutRetryThenFreshConnectionAvoidsItOrLocalGuard() =
        runBlocking {
            AccountDeletionFixtures.requireLocalAvd()
            if (!AccountDeletionFixtures.online()) {
                LocalEnvironment.requireSafe()
                return@runBlocking
            }
            val oldEvents = Connections()
            val old = client(oldEvents, noIdle = false)
            val freshEvents = Connections()
            val fresh = client(freshEvents, noIdle = true)
            try {
                assertEquals("timeout=5", probe(old))
                val idleStart = SystemClock.elapsedRealtime()
                delay(7_000)
                check(SystemClock.elapsedRealtime() - idleStart < 9_500) {
                    "Experiment left the observed emulator 6–10 second stale-health window"
                }
                val failure =
                    try {
                        probe(old)
                        null
                    } catch (error: IOException) {
                        error
                    }
                assertNotNull(
                    "Default pool must reproduce the actual idle EOF, not hide it with retry",
                    failure,
                )
                assertTrue(
                    generateSequence<Throwable>(failure) { it.cause }.any { it is EOFException }
                )
                assertEquals(
                    "No automatic new connection/retry was allowed",
                    1,
                    oldEvents.connects.get(),
                )
                assertEquals(2, oldEvents.used.size)
                assertSame(oldEvents.used[0], oldEvents.used[1])

                assertEquals("timeout=5", probe(fresh))
                delay(7_000)
                assertEquals("timeout=5", probe(fresh))
                assertEquals(
                    "Two explicit calls use exactly two new connections, not a retried request",
                    2,
                    freshEvents.connects.get(),
                )
                assertEquals(2, freshEvents.used.size)
                assertNotSame(freshEvents.used[0], freshEvents.used[1])
                assertFalse(old.retryOnConnectionFailure)
                assertFalse(fresh.retryOnConnectionFailure)
            } finally {
                old.connectionPool.evictAll()
                fresh.connectionPool.evictAll()
            }
        }
}
