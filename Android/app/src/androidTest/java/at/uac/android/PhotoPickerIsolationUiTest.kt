package at.uac.android

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real picker isolated from Auth/Main/backend. Only process-owned synthetic albums are selected.
 */
@RunWith(AndroidJUnit4::class)
class PhotoPickerIsolationUiTest {
    @get:Rule val compose = createComposeRule()
    @Volatile private var completed = 0
    @Volatile private var result: Uri? = null
    private val context
        get() = AccountDeletionFixtures.context

    private fun content() {
        AccountDeletionFixtures.requireLocalAvd()
        compose.setContent {
            val picker =
                rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
                    result = uri
                    completed++
                }
            MaterialTheme {
                Button(
                    { picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) },
                    Modifier.testTag("picker-isolation-open"),
                ) {
                    Text("Open synthetic picker")
                }
            }
        }
    }

    private fun select(cancelFirst: Boolean) {
        val fixture = PhotoPickerFixtures.create(context, "UAC-Isolation")
        var primary: Throwable? = null
        try {
            val initialState = PhotoPickerFixtures.publishedState(context, fixture)
            var before = completed
            compose.runOnIdle { result = null }
            compose.onNodeWithTag("picker-isolation-open").assertIsDisplayed().performClick()
            compose.waitUntil(10_000) { PhotoPickerFixtures.focusedPickerWindow() }
            if (cancelFirst) {
                PhotoPickerFixtures.cancelFocusedPickerOnce()
                compose.waitUntil(15_000) {
                    completed == before + 1 && !PhotoPickerFixtures.pickerVisible()
                }
                assertNull(result)
                before = completed
                compose.onNodeWithTag("picker-isolation-open").assertIsDisplayed().performClick()
                compose.waitUntil(10_000) { PhotoPickerFixtures.focusedPickerWindow() }
            }
            try {
                PhotoPickerFixtures.selectOnlyPhoto(fixture)
            } catch (failure: Throwable) {
                throw AssertionError(
                    "Isolated picker: cancellation=$cancelFirst,before=[$initialState]," +
                        "after=[${PhotoPickerFixtures.publishedState(context, fixture)}]",
                    failure,
                )
            }
            compose.waitUntil(15_000) {
                completed == before + 1 && result != null && !PhotoPickerFixtures.pickerVisible()
            }
            val actual =
                context.contentResolver.openInputStream(requireNotNull(result))!!.use { input ->
                    val bytes = ByteArray(fixture.png.size + 1)
                    var used = 0
                    while (used < bytes.size) {
                        val read = input.read(bytes, used, bytes.size - used)
                        if (read < 0) break
                        used += read
                    }
                    bytes.copyOf(used)
                }
            assertArrayEquals(
                "The selected file must be exactly our synthetic PNG",
                fixture.png,
                actual,
            )
        } catch (failure: Throwable) {
            primary = failure
            throw failure
        } finally {
            try {
                if (PhotoPickerFixtures.focusedPickerWindow())
                    PhotoPickerFixtures.cancelFocusedPickerOnce()
                PhotoPickerFixtures.delete(context, fixture)
            } catch (cleanup: Throwable) {
                if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
            }
        }
    }

    @Test
    fun directlySelectsOneExactPublishedPhotoWithoutAuthOrBackend() {
        content()
        select(cancelFirst = false)
    }

    @Test
    fun cancellationThenSelectionAndNewAlbumDoNotReuseOldPickerContents() {
        content()
        repeat(2) { select(cancelFirst = true) }
    }
}
