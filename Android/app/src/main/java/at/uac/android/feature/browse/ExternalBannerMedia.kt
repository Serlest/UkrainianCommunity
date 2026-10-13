package at.uac.android.feature.browse

import at.uac.android.BuildConfig
import java.net.InetAddress
import java.net.Proxy
import java.net.URI
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import okhttp3.Authenticator
import okhttp3.CookieJar
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request

/** Only banner images may opt into external hosts. Content/avatar policy remains bucket-only. */
internal object ExternalBannerMediaPolicy {
    fun address(value: String): String? = runCatching {
        if (value.length !in 1..5_000 || value.any(Char::isISOControl)) return null
        val uri = URI(value)
        val host = uri.host?.lowercase() ?: return null
        if (
            uri.scheme != "https" ||
                uri.port !in setOf(-1, 443) ||
                uri.rawUserInfo != null ||
                uri.rawFragment != null ||
                host.endsWith('.') ||
                !host.contains('.') ||
                host.endsWith(".local") ||
                host.endsWith(".localhost") ||
                host.endsWith(".internal") ||
                host.endsWith(".invalid") ||
                host.any { it !in 'a'..'z' && it !in '0'..'9' && it != '-' && it != '.' }
        )
            return null
        // Literal addresses are unnecessary for public artwork and increase ambiguity.
        if (host.all { it.isDigit() || it == '.' }) return null
        value
    }
        .getOrNull()

    fun publicAddress(address: InetAddress): Boolean {
        if (
            address.isAnyLocalAddress ||
                address.isLoopbackAddress ||
                address.isLinkLocalAddress ||
                address.isSiteLocalAddress ||
                address.isMulticastAddress
        )
            return false
        val bytes = address.address.map { it.toInt() and 255 }
        return when (bytes.size) {
            4 -> {
                val a = bytes[0]
                val b = bytes[1]
                !(a == 0 ||
                    a == 10 ||
                    a == 127 ||
                    a >= 224 ||
                    (a == 100 && b in 64..127) ||
                    (a == 169 && b == 254) ||
                    (a == 172 && b in 16..31) ||
                    (a == 192 && (b == 0 || b == 168 || (b == 88 && bytes[2] == 99))) ||
                    (a == 198 && (b in 18..19 || (b == 51 && bytes[2] == 100))) ||
                    (a == 203 && b == 0 && bytes[2] == 113))
            }
            // Global unicast only; exclude special-use, documentation and tunnel ranges.
            16 ->
                (bytes[0] and 0xe0) == 0x20 &&
                    !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] <= 1) &&
                    !(bytes[0] == 0x20 &&
                        bytes[1] == 0x01 &&
                        bytes[2] == 0x0d &&
                        bytes[3] == 0xb8) &&
                    !(bytes[0] == 0x20 && bytes[1] == 0x02) &&
                    !(bytes[0] == 0x3f && bytes[1] == 0xff)
            else -> false
        }
    }
}

internal object ExternalBannerMedia {
    private val client =
        OkHttpClient.Builder()
            .proxy(Proxy.NO_PROXY)
            .cookieJar(CookieJar.NO_COOKIES)
            .authenticator(Authenticator.NONE)
            .proxyAuthenticator(Authenticator.NONE)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .connectTimeout(3, TimeUnit.SECONDS)
            .readTimeout(3, TimeUnit.SECONDS)
            .callTimeout(6, TimeUnit.SECONDS)
            .dns(
                object : Dns {
                    override fun lookup(hostname: String): List<InetAddress> {
                        val addresses = Dns.SYSTEM.lookup(hostname)
                        if (
                            addresses.isEmpty() ||
                                addresses.any { !ExternalBannerMediaPolicy.publicAddress(it) }
                        )
                            throw UnknownHostException("Banner host is not public")
                        return addresses
                    }
                }
            )
            .build()

    fun bytes(address: String, ensureActive: () -> Unit): ByteArray {
        check(!BuildConfig.USE_LOCAL_BACKEND)
        check(ExternalBannerMediaPolicy.address(address) == address)
        ensureActive()
        return client
            .newCall(Request.Builder().url(address).header("Accept", "image/*").build())
            .execute()
            .use { response ->
                check(response.code == 200)
                val body = checkNotNull(response.body)
                check(body.contentLength() <= PublicMediaPolicy.MAX_BYTES)
                check(body.contentType()?.type == "image")
                body.byteStream().use { PublicMediaPolicy.bytes(it, ensureActive) }
            }
    }
}
