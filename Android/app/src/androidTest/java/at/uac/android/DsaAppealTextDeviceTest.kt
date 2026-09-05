package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.dsaappeal.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual Android ICU only: no SDK, fixture accounts, network or legal submissions. */
@RunWith(AndroidJUnit4::class)
class DsaAppealTextDeviceTest {
    @Test
    fun combiningMarksAndEmojiAreLogicalCharactersNotUtf16() {
        for (character in listOf("е́", "😀", "👩‍💻", "🇺🇦", "👨‍👩‍👧‍👦")) {
            assertEquals(character, 1, AndroidDsaAppealCharacters.count(character))
            assertEquals(
                character,
                20,
                AndroidDsaAppealCharacters.review(character.repeat(20)).logicalCharacters,
            )
        }
    }

    @Test
    fun nineteenComplexCharactersCannotPassMinimumUsingCodeUnits() {
        try {
            AndroidDsaAppealCharacters.review("е́".repeat(19))
            fail("Below the logical-character minimum")
        } catch (error: DsaAppealTextException) {
            assertEquals(DsaAppealTextFailure.TOO_SHORT, error.failure)
        }
    }

    @Test
    fun normalizationIsVisibleAndCannotUseRemovedWhitespaceToPassMinimum() {
        val raw = " \uFEFF" + "абвгґдежзиіїйклмнопр" + "\n\t"
        val review = AndroidDsaAppealCharacters.review(raw)
        assertTrue(review.normalizationChanged)
        assertEquals(20, review.logicalCharacters)
        assertEquals("абвгґдежзиіїйклмнопр", review.reason)
        try {
            AndroidDsaAppealCharacters.review("а" + " ".repeat(30) + "б")
            fail("Collapsed whitespace is not an explanation")
        } catch (error: DsaAppealTextException) {
            assertEquals(DsaAppealTextFailure.TOO_SHORT, error.failure)
        }
    }

    @Test
    fun exactServerUtf16LimitStillAppliesAfterIcuCounting() {
        assertEquals(2_500, AndroidDsaAppealCharacters.review("😀".repeat(2_500)).logicalCharacters)
        try {
            AndroidDsaAppealCharacters.review("😀".repeat(2_500) + "a")
            fail("Over server UTF16 limit")
        } catch (error: DsaAppealTextException) {
            assertEquals(DsaAppealTextFailure.TOO_LONG, error.failure)
        }
    }

    @Test
    fun boundaryAdapterDoesNotSplitSupplementaryCharactersOrRetainInput() {
        assertEquals(0, AndroidDsaAppealCharacters.count(""))
        assertEquals(3, AndroidDsaAppealCharacters.count("a😀b"))
        assertEquals(1, AndroidDsaAppealCharacters.count("x"))
        assertEquals(
            "DsaAppealReviewedText(<redacted>)",
            AndroidDsaAppealCharacters.review("abcdefghijklmnopqrst").toString(),
        )
    }
}
