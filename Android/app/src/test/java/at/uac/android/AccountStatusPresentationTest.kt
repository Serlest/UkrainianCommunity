package at.uac.android

import at.uac.android.feature.accountstatus.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class AccountStatusPresentationTest {
    private val warning =
        AccountStatusVersion("own", "warned", "active", Instant.EPOCH, null, "Synthetic", null)
    private val session =
        AccountStatusSession("own", 1, AccountStatusObservation(warning, null), true, true)

    @Test
    fun newAuthWarningCoversBeforeObserverBindsIt() {
        assertTrue(AccountStatusState().coversContent(session))
        assertTrue(AccountStatusState(session.copy(revision = 0)).coversContent(session))
    }

    @Test
    fun exactAcknowledgementOrExplicitRemediationEscapeDoesNotReopenCover() {
        assertFalse(AccountStatusState(session = session, notice = null).coversContent(session))
        assertTrue(AccountStatusState(session = session, notice = warning).coversContent(session))
    }

    @Test
    fun oldPrivateNoticeDoesNotCoverGuestOrDifferentAccountWithoutNotice() {
        val old = AccountStatusState(session, warning)
        assertFalse(old.coversContent(null))
        assertFalse(
            old.coversContent(
                session.copy(uid = "second", observation = AccountStatusObservation(null, null))
            )
        )
    }

    @Test
    fun freshAlreadyAcknowledgedVersionDoesNotWaitForOldObserver() {
        val confirmed =
            session.copy(
                revision = 2,
                observation = AccountStatusObservation(warning, Instant.EPOCH),
            )
        assertFalse(AccountStatusState(session, warning).coversContent(confirmed))
    }

    @Test
    fun changedVersionClosesGateEvenAfterOldVersionWasEscaped() {
        val changed =
            session.copy(
                observation =
                    AccountStatusObservation(warning.copy(message = "Changed synthetic"), null)
            )
        assertTrue(AccountStatusState(session = session).coversContent(changed))
    }
}
