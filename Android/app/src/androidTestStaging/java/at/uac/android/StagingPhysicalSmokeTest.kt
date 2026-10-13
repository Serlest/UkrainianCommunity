package at.uac.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.testing.DebugAppCheckTestHelper
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Read-only physical-device gate for the isolated staging application. */
@RunWith(AndroidJUnit4::class)
class StagingPhysicalSmokeTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun stagingGuestShellStartsWithExactBackendBinding() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("at.serlest.ukrainiancommunity.staging", context.packageName)
        assertEquals("uac-android-test-20260903", BuildConfig.BACKEND_PROJECT_ID)

        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("tab-home").fetchSemanticsNodes().isNotEmpty()
        }
        listOf("tab-home", "tab-events", "tab-organizations", "tab-profile", "settings")
            .forEach { compose.onNodeWithTag(it).assertIsDisplayed() }

        val firebaseApps = FirebaseApp.getApps(context)
        assertTrue("Staging launch must initialize Firebase", firebaseApps.isNotEmpty())
        assertTrue(
            "Every initialized Firebase app must remain bound to staging",
            firebaseApps.all { it.options.projectId == "uac-android-test-20260903" },
        )

        val app = firebaseApps.single()
        DebugAppCheckTestHelper.fromInstrumentationArgs().withDebugProvider<Exception>(app) {
            val token = runBlocking { FirebaseAppCheck.getInstance(app).getAppCheckToken(true).await() }
            assertTrue("Staging App Check must return a non-empty token", token.token.isNotBlank())
        }
    }
}
