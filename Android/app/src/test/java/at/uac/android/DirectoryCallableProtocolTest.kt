package at.uac.android

import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import org.junit.Assert.*
import org.junit.Test

class DirectoryCallableProtocolTest {
    @Test fun editorPublicationAndDeletionReachTheirExistingServerEndpoints() {
        for (name in listOf("saveDirectoryCategory", "deleteDirectoryCategory")) {
            assertTrue(LocalCallableProtocol.endpoint(name).endsWith("/$name"))
            assertTrue(LocalCallableProtocol.nonIdempotent(name))
            assertEquals(LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(name, true, LocalCallableFailure.UNAVAILABLE))
        }
        assertTrue(LocalCallableProtocol.maximumRequestBytes("saveDirectoryCategory") > 800_000)
        assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes("deleteDirectoryCategory"))
    }
}
