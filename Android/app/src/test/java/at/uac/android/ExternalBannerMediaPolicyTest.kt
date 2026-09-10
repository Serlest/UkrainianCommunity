package at.uac.android

import at.uac.android.feature.browse.ExternalBannerMediaPolicy
import at.uac.android.feature.browse.PublicMediaPolicy
import java.net.InetAddress
import org.junit.Assert.*
import org.junit.Test

class ExternalBannerMediaPolicyTest {
    @Test
    fun externalHttpsIsOptInAndDoesNotWidenPublicContentPolicy() {
        val url = "https://images.community.example/banner.jpg?v=2"
        assertEquals(url, ExternalBannerMediaPolicy.address(url))
        assertNull(PublicMediaPolicy.address(url))
        assertNotNull(
            ExternalBannerMediaPolicy.address("https://images.community.example:443/photo.png")
        )
    }

    @Test
    fun credentialsLocalHostsLiteralIpsAndUnsafeSchemesAreRejected() {
        listOf(
                "http://images.community.example/photo.jpg",
                "https://user:pass@images.community.example/photo.jpg",
                "https://images.community.example:8443/photo.jpg",
                "https://images.community.example/photo.jpg#fragment",
                "https://localhost/photo.jpg",
                "https://printer.local/photo.jpg",
                "https://service.internal/photo.jpg",
                "https://host.localhost/photo.jpg",
                "https://127.0.0.1/photo.jpg",
                "https://2130706433/photo.jpg",
                "https://[::1]/photo.jpg",
                "https://127.1/photo.jpg",
                "file:///photo.jpg",
                "https://images.community.example./photo.jpg",
            )
            .forEach { assertNull(it, ExternalBannerMediaPolicy.address(it)) }
    }

    @Test
    fun dnsAnswersMustBePublicIncludingIpv6AndMappedAddresses() {
        listOf(
                "0.0.0.0",
                "10.1.2.3",
                "127.0.0.1",
                "169.254.169.254",
                "172.16.0.1",
                "192.168.1.1",
                "100.64.0.1",
                "198.18.0.1",
                "192.0.2.1",
                "198.51.100.1",
                "203.0.113.1",
                "224.0.0.1",
                "240.0.0.1",
                "::",
                "::1",
                "fe80::1",
                "fd00::1",
                "ff02::1",
                "2001:db8::1",
                "2002:7f00:1::1",
                "64:ff9b::7f00:1",
                "::ffff:127.0.0.1",
            )
            .forEach {
                assertFalse(it, ExternalBannerMediaPolicy.publicAddress(InetAddress.getByName(it)))
            }
        listOf("8.8.8.8", "1.1.1.1", "2606:4700:4700::1111").forEach {
            assertTrue(it, ExternalBannerMediaPolicy.publicAddress(InetAddress.getByName(it)))
        }
    }
}
