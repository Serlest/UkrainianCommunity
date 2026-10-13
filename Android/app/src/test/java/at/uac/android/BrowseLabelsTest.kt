package at.uac.android

import at.uac.android.feature.browse.ReadFailure
import at.uac.android.feature.browse.failureText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class BrowseLabelsTest {
    @Test
    fun offlineFailureUsesReleaseSafeGermanCopy() {
        val message = failureText(ReadFailure.OFFLINE, "de")

        assertEquals(
            "Inhalte sind derzeit nicht verfügbar. Keine passende gespeicherte Seite vorhanden.",
            message,
        )
        assertFalse(message.contains("Emulator", ignoreCase = true))
    }

    @Test
    fun offlineFailureUsesReleaseSafeUkrainianCopy() {
        val message = failureText(ReadFailure.OFFLINE, "uk")

        assertEquals(
            "Матеріали зараз недоступні. Відповідної збереженої сторінки немає.",
            message,
        )
        assertFalse(message.contains("емулятор", ignoreCase = true))
    }
}
