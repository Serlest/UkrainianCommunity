package at.uac.android

import at.uac.android.feature.directory.DirectoryDraftValidation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DirectorySourceUrlTest {
    @Test fun acceptsBareDomainAndUpgradesHttpWithoutDroppingPathOrQuery() {
        assertEquals("https://serlest.com", DirectoryDraftValidation.canonicalSourceUrl(" serlest.com "))
        assertEquals("https://serlest.com/path?x=1",
            DirectoryDraftValidation.canonicalSourceUrl("http://serlest.com/path?x=1"))
        assertEquals("https://serlest.com/path?x=1",
            DirectoryDraftValidation.canonicalSourceUrl("http://serlest.com:80/path?x=1"))
        assertEquals("https://serlest.com/path?x=1",
            DirectoryDraftValidation.canonicalSourceUrl("HTTPS://serlest.com/path?x=1"))
        assertEquals("https://example.org:8443/path?x=1",
            DirectoryDraftValidation.canonicalSourceUrl("https://example.org:8443/path?x=1"))
        assertEquals("https://xn--bcher-kva.example:8443/path?x=1",
            DirectoryDraftValidation.canonicalSourceUrl("https://bücher.example:8443/path?x=1"))
        assertEquals("https://serlest.com/path?next=https://example.com/a",
            DirectoryDraftValidation.canonicalSourceUrl("serlest.com/path?next=https://example.com/a"))
    }

    @Test fun rejectsUnsafeOrMalformedSourceAddresses() {
        for (address in listOf("ftp://serlest.com", "https://user@serlest.com",
            "serlest.com/a b", "serlest.com\\@other.example", "https://user@bücher.example/path",
            "https://bücher.example:99999/path", "https://", "")) {
            assertNull(address, DirectoryDraftValidation.canonicalSourceUrl(address))
        }
    }
}
