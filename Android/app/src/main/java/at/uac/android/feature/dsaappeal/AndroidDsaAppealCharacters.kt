package at.uac.android.feature.dsaappeal

import android.icu.text.BreakIterator
import java.util.Locale

/** Android ICU logical-character boundaries; do not replace with String.length or JVM iterator. */
object AndroidDsaAppealCharacters : DsaAppealCharacterCounter {
    override fun count(text: String): Int {
        require(text.length <= DsaAppealContract.MAX_RAW_UTF16)
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
        iterator.setText(text)
        iterator.first()
        var count = 0
        while (iterator.next() != BreakIterator.DONE) count++
        return count
    }

    fun review(raw: String): DsaAppealReviewedText = DsaAppealContract.review(raw, this)
}
