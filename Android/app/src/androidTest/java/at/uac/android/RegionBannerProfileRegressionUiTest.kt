package at.uac.android

import android.graphics.Bitmap
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.browse.*
import at.uac.android.feature.personal.*
import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.Assume.assumeTrue

/** Public production placements, isolated bundled content and a local image; no cloud writes. */
class RegionBannerProfileRegressionUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun captureBuild108Baseline() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("captureBaseline") == "true")
        journey(baseline = true)
    }
    @Test fun correctedRegionBannersAndProfileBackground() = journey(baseline = false)

    @Test fun durableGuestRegionAcrossRealProcessRestart() {
        val phase = InstrumentationRegistry.getArguments().getString("regionRestartPhase")
        assumeTrue(phase in listOf("seed", "verify"))
        val vm = compose.runOnIdle { ViewModelProvider(compose.activity)[BrowseViewModel::class.java] }
        if (phase == "seed") compose.runOnIdle { vm.preference("region", "tirol") }
        compose.waitUntil(20_000) { !vm.state.value.data.loading }
        assertEquals("tirol", vm.state.value.region)
        assertEquals("tirol", InstrumentationRegistry.getInstrumentation().targetContext
            .getSharedPreferences("uac-local", 0).getString("region", null))
    }

    private fun journey(baseline: Boolean) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val image = InstrumentationRegistry.getInstrumentation().context.assets
            .open("visual-tirol-banner.jpg").use { it.readBytes() }
        withLocalImageFixture(image) { url ->
            val fixtures = ContentJson.fixtures(context).toMutableMap()
            val sample = fixtures.getValue("featuredBanners/synthetic-banner-welcome")
            fixtures.keys.filter { it.startsWith("featuredBanners/") }.toList().forEach(fixtures::remove)
            fun banner(id: String, region: String?) = RawDocument(id, sample.fields + mapOf(
                "id" to id, "isActive" to true, "imageURL" to url,
                "visibleSections" to listOf("directory", "events", "home", "organizations"),
                "regionScope" to if (region == null) "allAustria" else "federalState",
                "federalState" to region, "startsAt" to null, "endsAt" to null,
            ))
            fixtures["featuredBanners/production-shape-all"] = banner("production-shape-all", null)
            fixtures["featuredBanners/production-shape-tirol"] = banner("production-shape-tirol", "tirol")
            val preferences = context.getSharedPreferences("region-banner-regression", 0)
            preferences.edit().putString("region", "kaernten").commit()
            fun model(): BrowseViewModel {
                val repository = ContentRepository(SyntheticContentSource(fixtures), MemoryContentCache())
                return BrowseViewModel(repository, repository, SavedStateHandle(), "de",
                    preferences.getString("region", "").orEmpty(), "light",
                    { key, value -> preferences.edit().putString(key, value).commit() })
            }
            var vm = compose.runOnIdle { model().also { it.bindAccount(NavigationAccount("test-profile")) } }
            if (!baseline) compose.runOnIdle { vm.synchronizeProfileRegion("test-profile", "tirol") }
            fun render() = compose.runOnIdle {
                compose.activity.setContent {
                    BrowseScreen(vm.state.collectAsState().value, vm, {}, accountContent = { route, language ->
                        Column(Modifier.verticalScroll(rememberScrollState())) {
                            if (route == "profile/edit") PersonalProfilePanel(
                                PersonalState(profile = PersonalProfile("test-profile", "",
                                    ProfileDraft(fullName = "UAC Test", displayName = "UAC Test", federalState = "tirol"), null)),
                                language, {}, {})
                            else GuestProfileContent(language, {}, {}, {})
                        }
                    })
                }
            }
            fun ready() { compose.waitUntil(20_000) { !vm.state.value.data.loading }; compose.waitForIdle() }
            fun capture(name: String) {
                val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
                try { File(context.cacheDir, "region-banner-${if (baseline) "before" else "after"}-$name.png")
                    .outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                } finally { bitmap.recycle() }
            }
            render(); ready()
            if (baseline) {
                assertEquals("kaernten", vm.state.value.region)
                assertTrue(vm.state.value.data.banners.isEmpty())
                capture("home-light")
            } else {
                assertEquals("tirol", vm.state.value.region)
                assertEquals("tirol", preferences.getString("region", null))
                for (route in listOf("home", "events", "organizations", "directory")) {
                    compose.runOnIdle { vm.navigate(route, true) }; ready()
                    assertEquals(2, vm.state.value.data.banners.size)
                    compose.onNodeWithTag("banner-hero").assertIsDisplayed()
                    compose.waitUntil(10_000) { compose.onAllNodesWithTag("loaded-media").fetchSemanticsNodes().isNotEmpty() }
                    capture("$route-tirol-light")
                }
                compose.runOnIdle { vm.preference("region", "kaernten"); vm.navigate("home", true) }; ready()
                assertEquals(listOf("production-shape-all"), vm.state.value.data.banners.map { it.id })
                capture("home-kaernten-light")
                compose.runOnIdle { vm.preference("region", "tirol") }; ready()
                assertEquals(2, vm.state.value.data.banners.size)
                // Recreate the model from the durable preference, as on a cold app launch.
                vm = compose.runOnIdle { model().also {
                    it.bindAccount(NavigationAccount("test-profile"))
                    it.synchronizeProfileRegion("test-profile", "tirol")
                } }
                render(); ready()
                assertEquals("tirol", vm.state.value.region)
                assertEquals(2, vm.state.value.data.banners.size)
                capture("home-restarted-tirol-light")
            }
            for (theme in listOf("light", "dark")) for (route in listOf("profile", "profile/edit", "settings")) {
                compose.runOnIdle { vm.preference("theme", theme); vm.navigate(route, true) }; ready()
                if (!baseline) compose.onNodeWithTag("uac-page-artwork").assertExists()
                capture("${route.replace('/', '-') }-$theme")
            }
        }
    }
}
