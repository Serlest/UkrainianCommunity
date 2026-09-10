package at.uac.android

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.*
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.contentlifecycle.*
import at.uac.android.feature.contentmedia.*
import at.uac.android.feature.contentplanning.*
import at.uac.android.feature.featuredmanagement.*
import at.uac.android.feature.gallery.*
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.organization.*
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import org.junit.Rule
import org.junit.Test

/** Populated UI branches; all service writes deliberately fail in the fake source. */
class Build86ContentVisualUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val now = Instant.parse("2026-09-10T10:00:00Z")
    private val title = "Зустріч української спільноти Тіролю · Begegnung der Familien in Tirol"
    private val actor = OrganizationSession("visual86-owner", 86, true, "Owner", "user")
    private val owner = ModerationSession(actor.uid, 86, "owner", true)
    private val organization by lazy {
        val draft =
            OrganizationDraft(
                "visual86-org",
                "Українська спільнота Тіролю / Gemeinschaft Tirol",
                "A complete synthetic community organization",
                region = "tirol",
                city = "Innsbruck",
            )
        OrganizationContract.record(
            RawDocument(
                draft.id,
                OrganizationContract.create(draft, actor, now) +
                    mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
            ),
            actor,
        )
    }

    @Composable
    private fun Host(language: String, theme: String, content: @Composable () -> Unit) {
        SideEffect {
            WindowCompat.getInsetsController(
                    compose.activity.window,
                    compose.activity.window.decorView,
                )
                .apply {
                    isAppearanceLightStatusBars = theme == "light"
                    isAppearanceLightNavigationBars = theme == "light"
                }
        }
        UacTheme(theme) {
            UacPageBackground(Modifier.fillMaxSize(), plain = true) {
                Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                    UacHeader(
                        language,
                        true,
                        { compose.activity.onBackPressedDispatcher.onBackPressed() },
                        {},
                        compact = true,
                    )
                    Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp)) {
                        CompositionLocalProvider(
                            LocalEmbeddedNavigation provides true,
                            content = content,
                        )
                    }
                }
            }
        }
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        // Root registration order is not window z-order. Capturing the last root can
        // silently return a cropped background while a protected dialog is visible.
        val dialogs = compose.onAllNodes(isDialog()).fetchSemanticsNodes()
        check(dialogs.size <= 1) { "Unexpected stacked dialogs before screenshot: $name" }
        val target = if (dialogs.isNotEmpty()) compose.onNode(isDialog()) else compose.onRoot()
        val bitmap = target.assertIsDisplayed().captureToImage().asAndroidBitmap()
        try {
            File(instrumentation.targetContext.cacheDir, "build86-content-$name.png")
                .outputStream()
                .use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        } finally {
            bitmap.recycle()
        }
    }

    private fun lazyScroll(list: String, tag: String) =
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))

    private fun columnScroll(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun draft(kind: ContentKind) =
        AuthoringContract.newDraft(kind, organization, now)
            .copy(
                id = "visual86-${kind.collection}",
                title = title,
                summary = "Зустріч для родин, обмін досвідом і знайомство з громадою.",
                body =
                    "Запрошуємо на зустріч спільноти. Програма: знайомство, спільна розмова, практичні запитання та час для дітей.\n\nTreffen der Gemeinschaft mit Austausch und Informationen für Familien.",
                germanTitle = "Familientreffen der ukrainischen Gemeinschaft in Tirol",
                germanSummary = "Begegnung, Austausch und Informationen für Familien.",
                germanBody =
                    "Wir laden zu einem gemeinsamen Treffen mit Gesprächen und Informationen ein.",
            )
            .let {
                it.copy(
                    event =
                        it.event.copy(
                            venue = "Gemeinschaftshaus",
                            city = "Innsbruck",
                            address = "Museumstraße 1",
                            organizer = "Gemeinschaft Tirol",
                        )
                )
            }

    private fun item(kind: ContentKind): AuthoringItem {
        val d = draft(kind)
        return AuthoringContract.item(
            kind,
            RawDocument(
                d.id,
                AuthoringContract.submission(d, organization, actor, null, now).fields,
            ),
            organization.id,
            AuthoringStatus.APPROVED,
            actor,
        )
    }

    private fun jpeg(): ByteArray {
        val bitmap =
            Bitmap.createBitmap(160, 90, Bitmap.Config.ARGB_8888).apply {
                eraseColor(android.graphics.Color.rgb(40, 110, 170))
            }
        return try {
            ByteArrayOutputStream()
                .also { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
                .toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    private fun planningDraft(state: ContentPlanningState) =
        ContentPlanningDraft(
            "a".repeat(40),
            3,
            owner.uid,
            ContentPlanningKind.EVENT,
            state,
            title,
            mapOf(
                "title" to title,
                "summary" to "Перевірений короткий опис",
                "body" to "Повний текст матеріалу",
            ),
            listOf(
                ContentPlanningSource(
                    "https://example.org/event",
                    "Офіційна програма заходу та умови участі / Vollständiges Veranstaltungsprogramm",
                    true,
                    now,
                )
            ),
            listOf("Дату та місце звірено з першоджерелом", "Übersetzung geprüft"),
            if (state == ContentPlanningState.ATTENTION) listOf("germanBody", "venue")
            else emptyList(),
            now,
            now,
            if (state == ContentPlanningState.SCHEDULED) now.plusSeconds(86400) else null,
            null,
            null,
            if (state == ContentPlanningState.FAILED) "Verbindung unterbrochen · перевірте стан"
            else null,
            null,
            if (state == ContentPlanningState.COMPLETED) "published-visual" else null,
            null,
            null,
            null,
            null,
        )

    private fun planning(language: String, theme: String) {
        val current = mutableStateOf(ContentPlanningUiState(session = owner, visible = true))
        compose.setContent {
            Host(language, theme) {
                ContentPlanningContent(
                    current.value,
                    language,
                    onClose = { current.value = current.value.copy(selected = null) },
                )
            }
        }
        ContentPlanningState.entries.forEach { status ->
            val d = planningDraft(status)
            compose.runOnIdle {
                current.value =
                    current.value.copy(
                        selectedSection = d.section,
                        selected = null,
                        sections =
                            mapOf(
                                d.section to ContentPlanningSectionState(listOf(d), loaded = true)
                            ),
                    )
            }
            lazyScroll("content-planning", "content-planning-draft-${d.id}")
            capture("planning-list-$status-$language-$theme")
            compose.runOnIdle {
                current.value =
                    current.value.copy(
                        selected = d,
                        organizations =
                            listOf(ContentPlanningOrganization("visual86-org", organization.name)),
                    )
            }
            capture("planning-detail-$status-$language-$theme")
            if (d.canPublish) {
                lazyScroll("content-planning-detail", "content-planning-organization-visual86-org")
                compose.onNodeWithTag("content-planning-organization-visual86-org").performClick()
                lazyScroll("content-planning-detail", "content-planning-review")
                compose.onNodeWithTag("content-planning-review").assertIsEnabled()
                capture("planning-organization-$status-$language-$theme")
            }
            if (status == ContentPlanningState.READY) {
                for (action in listOf("archive", "delete")) {
                    lazyScroll("content-planning-detail", "content-planning-$action")
                    compose.onNodeWithTag("content-planning-$action").performClick()
                    compose.onNodeWithTag("content-planning-confirm-$action").assertIsDisplayed()
                    capture("planning-$action-dialog-$language-$theme")
                    compose
                        .onNodeWithText(if (language == "uk") "Скасувати" else "Abbrechen")
                        .performClick()
                    compose.onNodeWithTag("content-planning-confirm-$action").assertDoesNotExist()
                    compose.onNodeWithTag("content-planning-detail").assertIsDisplayed()
                }
            }
        }
        ContentPlanningRecoveryPhase.entries.forEach { phase ->
            compose.runOnIdle {
                current.value =
                    current.value.copy(
                        selected = null,
                        recovery = ContentPlanningRecovery("a".repeat(40), null, null, phase),
                        error = ContentPlanningFailure.UNCONFIRMED,
                    )
            }
            lazyScroll("content-planning", "content-planning-reconcile")
            capture("planning-recovery-$phase-$language-$theme")
        }
    }

    @Test fun planningUkrainianDark() = planning("uk", "dark")

    @Test fun planningGermanLight() = planning("de", "light")

    private fun authoring(language: String, theme: String) {
        val current = mutableStateOf(AuthoringState())
        compose.setContent {
            Host(language, theme) {
                AuthoringContent(
                    current.value,
                    language,
                    AuthoringActions(
                        change = { change ->
                            current.value =
                                current.value.copy(draft = change(current.value.draft!!))
                        }
                    ),
                )
            }
        }
        for (kind in listOf(ContentKind.NEWS, ContentKind.EVENTS)) {
            val d = draft(kind)
            val base =
                AuthoringState(
                    actor,
                    organization.id,
                    visible = true,
                    kind = kind,
                    hub =
                        AuthoringHub(
                            organization,
                            kind,
                            AuthoringStatus.APPROVED,
                            AuthoringPage(listOf(item(kind)), null),
                        ),
                    fresh = true,
                    recoveryLoaded = true,
                )
            compose.runOnIdle { current.value = base }
            columnScroll("authoring-item-${d.id}")
            capture("authoring-list-$kind-$language-$theme")
            compose.runOnIdle {
                current.value =
                    base.copy(
                        draft = d,
                        draftOrganization = organization,
                        editorFresh = true,
                        draftSaved = true,
                    )
            }
            for (section in 0..if (kind == ContentKind.EVENTS) 3 else 1) {
                columnScroll("authoring-section-$section")
                compose.onNodeWithTag("authoring-section-$section").performClick()
                val first =
                    listOf(
                        "authoring-title",
                        "authoring-additional-category-other",
                        "authoring-city",
                        "authoring-organizer",
                    )[section]
                columnScroll(if (section == 1) "authoring-tags" else first)
                capture("authoring-editor-$kind-$section-$language-$theme")
            }
            compose.runOnIdle { current.value = current.value.copy(preview = true) }
            capture("authoring-preview-$kind-$language-$theme")
            compose.runOnIdle {
                current.value =
                    current.value.copy(
                        preview = false,
                        confirmation =
                            AuthoringContract.submission(d, organization, actor, null, now),
                    )
            }
            compose.onNodeWithTag("authoring-confirm").assertIsDisplayed()
            capture("authoring-confirm-$kind-$language-$theme")
            compose.runOnIdle {
                current.value =
                    current.value.copy(
                        confirmation = null,
                        uncertain = AuthoringContract.submission(d, organization, actor, null, now),
                        recoveryChecked = true,
                    )
            }
            columnScroll("authoring-recover")
            capture("authoring-recovery-$kind-$language-$theme")
            compose.runOnIdle {
                current.value =
                    base.copy(draft = d, draftOrganization = organization, editorFresh = true)
            }
            compose.onNodeWithTag("back").performClick()
            capture("authoring-leave-$kind-$language-$theme")
            compose
                .onNodeWithText(if (language == "uk") "Редагувати далі" else "Weiter bearbeiten")
                .performClick()
            compose
                .onNodeWithText(if (language == "uk") "Залишити форму?" else "Formular verlassen?")
                .assertDoesNotExist()
        }
    }

    @Test fun authoringUkrainianDark() = authoring("uk", "dark")

    @Test fun authoringGermanLight() = authoring("de", "light")

    private fun coverAndLifecycle(language: String, theme: String) {
        val route = mutableStateOf("cover")
        val cover = mutableStateOf(ContentCoverState())
        val life = mutableStateOf(ContentLifecycleState())
        compose.setContent {
            Host(language, theme) {
                if (route.value == "cover")
                    ContentCoverContent(cover.value, language, ContentCoverActions())
                else ContentLifecycleContent(life.value, language, ContentLifecycleActions())
            }
        }
        for (kind in listOf(ContentKind.NEWS, ContentKind.EVENTS)) {
            val i = item(kind)
            val snapshot =
                ContentCoverSnapshot(
                    ContentCoverTarget(organization.id, kind, i.id),
                    organization,
                    i,
                )
            val photo = PreparedContentCover(jpeg(), 160, 90)
            val base =
                ContentCoverState(
                    actor,
                    snapshot.target,
                    visible = true,
                    snapshot = snapshot,
                    fresh = true,
                    prepared = photo,
                    preparedFor = snapshot,
                )
            compose.runOnIdle {
                route.value = "cover"
                cover.value = base
            }
            columnScroll("content-cover-preview")
            capture("cover-preview-$kind-$language-$theme")
            columnScroll("content-cover-upload")
            capture("cover-actions-$kind-$language-$theme")
            compose.runOnIdle {
                cover.value = base.copy(confirmation = ContentCoverIntent.Upload(snapshot, photo))
            }
            capture("cover-upload-dialog-$kind-$language-$theme")
            if (kind == ContentKind.NEWS) {
                val removable =
                    snapshot.copy(
                        item =
                            i.copy(
                                fields =
                                    i.fields +
                                        ("imageURL" to "https://example.invalid/existing.jpg")
                            )
                    )
                compose.runOnIdle {
                    cover.value =
                        base.copy(
                            snapshot = removable,
                            prepared = null,
                            confirmation = ContentCoverIntent.Remove(removable),
                        )
                }
                capture("cover-remove-dialog-$kind-$language-$theme")
            }
            compose.runOnIdle {
                cover.value =
                    base.copy(
                        uncertain = ContentCoverIntent.Upload(snapshot, photo),
                        recoveryChecked = true,
                    )
            }
            columnScroll("content-cover-recover")
            capture("cover-recovery-$kind-$language-$theme")
            val ls =
                ContentLifecycleSnapshot(
                    ContentLifecycleTarget(organization.id, kind, i.id),
                    organization,
                    i,
                )
            val lb = ContentLifecycleState(actor, ls.target, true, ls, true)
            compose.runOnIdle {
                route.value = "lifecycle"
                life.value = lb
            }
            capture("lifecycle-target-$kind-$language-$theme")
            columnScroll("content-lifecycle-request")
            capture("lifecycle-action-$kind-$language-$theme")
            compose.runOnIdle { life.value = lb.copy(confirmation = ContentLifecycleIntent(ls)) }
            capture("lifecycle-confirm-$kind-$language-$theme")
            compose.runOnIdle {
                life.value =
                    lb.copy(
                        uncertain = ContentLifecycleIntent(ls),
                        observed = ContentLifecycleObserved.UNCHANGED,
                    )
            }
            columnScroll("content-lifecycle-recover")
            capture("lifecycle-recovery-$kind-$language-$theme")
            compose.onNodeWithTag("back").performClick()
            capture("lifecycle-leave-$kind-$language-$theme")
            compose
                .onNodeWithText(if (language == "uk") "Залишитися тут" else "Hier bleiben")
                .performClick()
            compose
                .onNodeWithText(if (language == "uk") "Повернутися назад?" else "Zurückgehen?")
                .assertDoesNotExist()
            compose.runOnIdle {
                life.value =
                    lb.copy(
                        confirmed =
                            ContentLifecycleConfirmation(
                                ls,
                                ContentLifecycleReceipt.Deleted(ls.target, now),
                            )
                    )
            }
            columnScroll("content-lifecycle-confirmed")
            capture("lifecycle-complete-$kind-$language-$theme")
        }
    }

    @Test fun mediaLifecycleUkrainianDark() = coverAndLifecycle("uk", "dark")

    @Test fun mediaLifecycleGermanLight() = coverAndLifecycle("de", "light")

    private fun pickers(language: String, theme: String) {
        compose.setContent {
            Host(language, theme) {
                AuthoringDateTime(
                    "Дата / Datum",
                    now,
                    true,
                    language,
                    true,
                    java.time.ZoneId.of("Europe/Vienna"),
                    "visual86-picker",
                ) {}
            }
        }
        for (picker in listOf("date", "time")) {
            compose.onNodeWithTag("visual86-picker-$picker").performClick()
            capture("authoring-$picker-picker-$language-$theme")
            compose
                .onNodeWithText(if (language == "uk") "Скасувати" else "Abbrechen")
                .performClick()
            compose.onNodeWithTag("visual86-picker-date").assertIsDisplayed()
            compose
                .onNodeWithText(if (language == "uk") "Застосувати" else "Übernehmen")
                .assertDoesNotExist()
        }
    }

    @Test fun pickersUkrainianDark() = pickers("uk", "dark")

    @Test fun pickersGermanLight() = pickers("de", "light")

    private fun gallery(language: String, theme: String) {
        val target = GalleryTarget(organization.id, "visual86-photo")
        val photo =
            GalleryPhoto(
                target,
                GalleryContract.alias(target, "synthetic-token"),
                title,
                actor.uid,
                now,
                null,
            )
        // Private gallery fixture uses the authorized decoded-preview branch, never a cloud URL.
        val org =
            RawDocument(
                organization.id,
                organization.fields + ("moderationStatus" to "pendingReview"),
            )
        val snapshot = GallerySnapshot(org, listOf(photo), false, 1)
        val prepared = PreparedGalleryPhoto(jpeg(), 160, 90)
        val base = GalleryState(actor, organization.id, true, snapshot, fresh = true)
        val current = mutableStateOf(base)
        compose.setContent {
            Host(language, theme) { GalleryContent(current.value, language, GalleryActions()) }
        }
        lazyScroll("gallery-list", "gallery-photo-${target.photoId}")
        capture("gallery-list-$language-$theme")
        compose.runOnIdle { current.value = base.copy(prepared = prepared, caption = title) }
        lazyScroll("gallery-list", "gallery-prepared")
        capture("gallery-selected-$language-$theme")
        lazyScroll("gallery-list", "gallery-upload")
        capture("gallery-caption-actions-$language-$theme")
        val upload = GalleryUploadIntent(target, title, prepared)
        for ((name, confirmation) in
            listOf(
                "upload" to GalleryConfirmation.Upload(upload),
                "replace" to GalleryConfirmation.Upload(upload.copy(replacing = photo)),
                "delete" to GalleryConfirmation.Remove(photo),
            )) {
            compose.runOnIdle { current.value = base.copy(confirmation = confirmation) }
            compose.onNodeWithTag("gallery-confirm").assertIsDisplayed()
            capture("gallery-$name-dialog-$language-$theme")
        }
        val pending =
            GalleryJournalEntry(
                GalleryContract.accountHash(actor.uid),
                target,
                GalleryPhase.CREATE_SUBMITTED,
                "a".repeat(64),
                GalleryContract.hashText(title),
                GalleryContract.accountHash(actor.uid),
                "synthetic-token",
            )
        compose.runOnIdle {
            current.value =
                base.copy(
                    pending = listOf(pending),
                    recovery = GalleryRecovery.CLEANUP_AVAILABLE,
                    recoveryFor = pending,
                )
        }
        lazyScroll("gallery-list", "gallery-cleanup-${target.photoId}")
        capture("gallery-cleanup-$language-$theme")
        compose.runOnIdle {
            current.value = current.value.copy(confirmation = GalleryConfirmation.Cleanup(pending))
        }
        capture("gallery-cleanup-dialog-$language-$theme")
        compose.runOnIdle {
            current.value =
                base.copy(preview = GalleryBlob(jpeg(), "synthetic-token"), previewPhoto = photo)
        }
        compose.onNodeWithTag("gallery-preview-image").assertIsDisplayed()
        capture("gallery-viewer-$language-$theme")
        compose.runOnIdle { current.value = base.copy(prepared = prepared) }
        compose.onNodeWithTag("back").performClick()
        capture("gallery-leave-dialog-$language-$theme")
    }

    @Test fun galleryUkrainianDark() = gallery("uk", "dark")

    @Test fun galleryGermanLight() = gallery("de", "light")

    private fun featured(language: String, theme: String) {
        val d =
            FeaturedDraft(
                "visual86-banner",
                internalName = "Осіння програма спільноти / Herbstprogramm",
                localizations =
                    mapOf(
                        "uk" to
                            FeaturedLocalized(title, "Зустрічі, підтримка та корисні матеріали"),
                        "de" to
                            FeaturedLocalized(
                                "Herbstprogramm für Familien in Tirol",
                                "Treffen, Unterstützung und hilfreiche Informationen",
                            ),
                    ),
                priority = 12,
                sections = FeaturedSection.entries.toSet(),
            )
        val banner =
            FeaturedBanner(d, FeaturedVersion(d.id, now, "visual"), now, owner.uid, owner.uid)
        val source =
            object : FeaturedManagementSource {
                override suspend fun list(session: ModerationSession) = listOf(banner)

                override suspend fun find(session: ModerationSession, id: String) = banner

                override suspend fun save(
                    session: ModerationSession,
                    draft: FeaturedDraft,
                    create: Boolean,
                ): FeaturedReceipt = error("Visual test cannot write")

                override suspend fun setActive(
                    session: ModerationSession,
                    id: String,
                    active: Boolean,
                ): FeaturedReceipt = error("Visual test cannot write")

                override suspend fun delete(
                    session: ModerationSession,
                    id: String,
                ): FeaturedReceipt = error("Visual test cannot delete")

                override suspend fun upload(
                    session: ModerationSession,
                    bannerId: String,
                    jpeg: ByteArray,
                ): String = error("Visual test cannot upload")
            }
        val model =
            FeaturedManagementViewModel(
                FeaturedManagementRepository(source) { owner },
                FeaturedImagePreparation { error("No picker in visual test") },
            )
        compose.setContent {
            Host(language, theme) { FeaturedManagementScreen(model, owner, language, {}) }
        }
        compose.waitUntil(5000) {
            model.state.value.banners.isNotEmpty() && !model.state.value.loading
        }
        lazyScroll("featured-list", "featured-edit-${d.id}")
        capture("featured-list-$language-$theme")
        compose.onNodeWithTag("featured-delete-${d.id}").performScrollTo().performClick()
        capture("featured-delete-confirm-$language-$theme")
        compose.runOnIdle { model.edit(banner) }
        for (tag in
            listOf(
                "featured-internal-name",
                "featured-title-uk",
                "featured-title-de",
                "featured-image-pick",
            )) {
            lazyScroll("featured-editor", tag)
            capture("$tag-$language-$theme")
        }
        for (action in FeaturedAction.entries) {
            compose.runOnIdle { model.change { it.copy(action = action) } }
            lazyScroll("featured-editor", "featured-action-${action.wire}")
            capture("featured-action-${action.wire}-$language-$theme")
        }
        for (section in FeaturedSection.entries) {
            lazyScroll("featured-editor", "featured-section-${section.wire}")
            capture("featured-section-${section.wire}-$language-$theme")
        }
        compose.runOnIdle {
            model.change { it.copy(region = FeaturedRegion.FEDERAL_STATE, federalState = "tirol") }
        }
        for (tag in
            listOf("featured-state", "featured-priority", "featured-duration", "featured-save")) {
            lazyScroll("featured-editor", tag)
            capture("$tag-$language-$theme")
        }
        compose.onNodeWithTag("back").performClick()
        capture("featured-leave-editor-dialog-$language-$theme")
    }

    @Test fun featuredUkrainianDark() = featured("uk", "dark")

    @Test fun featuredGermanLight() = featured("de", "light")
}
