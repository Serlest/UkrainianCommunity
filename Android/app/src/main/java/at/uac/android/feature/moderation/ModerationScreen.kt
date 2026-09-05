package at.uac.android.feature.moderation

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.feature.browse.PublicImage
import at.uac.android.feature.browse.tr
import at.uac.android.feature.organizationreview.*

data class ModerationActions(
    val back: () -> Unit = {},
    val refresh: () -> Unit = {},
    val retry: (ModerationKind) -> Unit = {},
    val open: (ModerationTarget) -> Unit = {},
    val search: (String) -> Unit = {},
    val filter: (ModerationKind?) -> Unit = {},
    val sort: (ModerationSort) -> Unit = {},
)

@Composable
fun ModerationScreen(
    model: ModerationViewModel,
    session: ModerationSession?,
    section: ModerationSection,
    language: String,
    onBack: () -> Unit,
    requestedOrganizationId: String? = null,
    interactive: Boolean = true,
    decisions: ModerationDecisionViewModel? = null,
    organizationReviews: OrganizationReviewViewModel? = null,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    var presentation by remember(model) { mutableStateOf<ModerationPresentation?>(null) }
    LifecycleResumeEffect(listOf(session, section, requestedOrganizationId, interactive)) {
        val owned = if (interactive) model.present(section, requestedOrganizationId) else null
        presentation = owned
        onPauseOrDispose {
            owned?.let(model::dismiss)
            if (presentation === owned) presentation = null
        }
    }
    // Reading state drives composition; the independent live supplier vetoes a delayed host bind.
    val projected =
        if (stored.session == session && interactive && model.owns(presentation))
            model.snapshot(session, section)
        else ModerationState(section = section)
    val guarded: (() -> Unit) -> Unit = { action ->
        if (interactive && model.owns(presentation) && model.isCurrent(session, section)) action()
    }
    val back = {
        if (projected.selected != null) guarded { model.closePreview() }
        else
            presentation
                ?.takeIf { model.owns(it) }
                ?.let {
                    model.dismiss(it)
                    onBack()
                }
        Unit
    }
    BackHandler(enabled = interactive, onBack = back)
    // Content's atomic receipt contract must never be reused for organization callables.
    val decisionModel = decisions?.takeIf { section == ModerationSection.CONTENT }
    val organizationModel = organizationReviews?.takeIf {
        section == ModerationSection.ORGANIZATION_REQUESTS
    }
    val decisionState = decisionModel?.let { value ->
        val decisionStored by
            value.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
        if (decisionStored.session == session && projected.visible) value.snapshot(session)
        else ModerationDecisionState()
    }
    val reviewed =
        projected.preview
            ?.takeIf { !projected.previewLoading && projected.previewError == null }
            ?.reviewVersion
    SideEffect {
        decisionModel?.bindView(session, reviewed, presentation) {
            val current = model.snapshot(session, section)
            interactive &&
                model.owns(presentation) &&
                model.isCurrent(session, section) &&
                (reviewed == null ||
                    !current.previewLoading &&
                        current.previewError == null &&
                        current.selected == reviewed.target &&
                        current.preview?.reviewVersion == reviewed)
        }
    }
    LaunchedEffect(decisionState?.completion) {
        if ((decisionState?.completion ?: 0) > 0) guarded { model.refresh() }
    }
    val organizationState = organizationModel?.let { value ->
        val organizationStored by
            value.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
        if (organizationStored.session == session && projected.visible) value.snapshot(session)
        else OrganizationReviewState()
    }
    val organizationPreview =
        projected.preview?.takeIf {
            !projected.previewLoading &&
                projected.previewError == null &&
                projected.selected == it.item.target &&
                it.item.target.kind == ModerationKind.ORGANIZATION
        }
    val organizationTarget = organizationPreview?.item?.target
    val organizationFingerprint = organizationPreview?.organizationReviewFingerprint
    SideEffect {
        organizationModel?.bindView(
            session,
            organizationTarget,
            organizationFingerprint,
            presentation,
            hostIsCurrent = {
                interactive && model.owns(presentation) && model.isCurrent(session, section)
            },
        ) {
            val current = model.snapshot(session, section)
            organizationTarget == null ||
                !current.previewLoading &&
                    current.previewError == null &&
                    current.selected == organizationTarget &&
                    current.preview?.item?.target == organizationTarget &&
                    current.preview.organizationReviewFingerprint == organizationFingerprint
        }
    }
    LaunchedEffect(organizationState?.completion) {
        if ((organizationState?.completion ?: 0) > 0) guarded { model.refresh() }
    }
    ModerationContent(
        projected,
        language,
        ModerationActions(
            back,
            { guarded { model.refresh() } },
            { kind -> guarded { model.refresh(kind) } },
            { target -> guarded { model.select(target) } },
            { text -> guarded { model.search(text) } },
            { kind -> guarded { model.filter(kind) } },
            { sort -> guarded { model.sort(sort) } },
        ),
        decisionContent =
            if (decisionModel != null && decisionState != null) {
                {
                    ModerationDecisionPanel(
                        decisionState,
                        reviewed,
                        language,
                        ModerationDecisionActions(
                            { choice -> guarded { decisionModel.request(choice) } },
                            { guarded { decisionModel.confirm() } },
                            decisionModel::cancelConfirmation,
                            { pending -> guarded { decisionModel.reconcile(pending) } },
                            { guarded { decisionModel.refreshPending() } },
                        ),
                    )
                }
            } else if (organizationModel != null && organizationState != null) {
                {
                    if (organizationPreview != null && organizationFingerprint == null) {
                        Text(
                            tr(
                                language,
                                "Dieser Antrag ist nur lesbar: Status oder Rohdaten erlauben keine sichere Entscheidung.",
                                "Ця заявка доступна лише для перегляду: її статус або вихідні дані не дозволяють безпечного рішення.",
                            ),
                            Modifier.testTag("organization-review-preview-read-only"),
                        )
                    }
                    OrganizationReviewPanel(
                        organizationState,
                        language,
                        OrganizationReviewActions(
                            request = { action -> guarded { organizationModel.request(action) } },
                            editText = { text -> guarded { organizationModel.editText(text) } },
                            confirm = { guarded { organizationModel.confirm() } },
                            cancel = organizationModel::cancelConfirmation,
                            refresh = { guarded { organizationModel.refresh() } },
                            refreshPending = { guarded { organizationModel.refreshPending() } },
                            reconcile = { entry -> guarded { organizationModel.reconcile(entry) } },
                        ),
                    )
                }
            } else null,
    )
}

@Composable
fun ModerationContent(
    state: ModerationState,
    language: String,
    actions: ModerationActions,
    decisionContent: (@Composable () -> Unit)? = null,
) {
    val accessible = state.visible && state.session?.allowed == true
    LazyColumn(
        Modifier.fillMaxSize().imePadding().testTag("moderation-list"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("header") {
            TextButton(actions.back, Modifier.testTag("moderation-back")) {
                Text(tr(language, "Zurück", "Назад"))
            }
            Text(
                tr(
                    language,
                    if (state.section == ModerationSection.CONTENT) "Inhalte prüfen"
                    else "Organisationsanträge",
                    if (state.section == ModerationSection.CONTENT) "Перевірка матеріалів"
                    else "Заявки організацій",
                ),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                tr(
                    language,
                    if (decisionContent == null)
                        "Geschützte Vorschau. Entscheidungen sind in diesem Schritt noch nicht verfügbar."
                    else if (state.section == ModerationSection.ORGANIZATION_REQUESTS)
                        "Zugriff und Vorschau werden vor dem Senden erneut geprüft. Gleichzeitige Serveränderungen bleiben möglich; kein automatischer Wiederholungsversuch."
                    else
                        "Geschützte Vorschau. Entscheidungen beziehen sich nur auf die vollständig gelesene Version.",
                    if (decisionContent == null)
                        "Захищений перегляд. На цьому етапі прийняття рішень ще недоступне."
                    else if (state.section == ModerationSection.ORGANIZATION_REQUESTS)
                        "Перед надсиланням доступ і перегляд перевіряються знову. Одночасні зміни на сервері можливі; автоматичного повтору немає."
                    else "Захищений перегляд. Рішення стосується лише повністю прочитаної версії.",
                ),
                Modifier.testTag("moderation-read-only"),
            )
        }
        if (accessible && decisionContent != null && state.selected == null)
            item("decision-recovery") { decisionContent() }
        if (!accessible)
            item("denied") {
                Text(
                    moderationFailureText(
                        if (state.session == null) ModerationFailure.SIGN_IN
                        else if (!state.session.ready) ModerationFailure.NOT_READY
                        else ModerationFailure.DENIED,
                        language,
                    ),
                    Modifier.testTag("moderation-denied"),
                )
            }
        else if (state.selected != null) {
            item("preview-refresh") {
                TextButton(actions.refresh, Modifier.testTag("moderation-preview-refresh")) {
                    Text(tr(language, "Vorschau erneut prüfen", "Перевірити перегляд знову"))
                }
            }
            if (state.previewLoading)
                item("preview-loading") {
                    LinearProgressIndicator(
                        Modifier.fillMaxWidth().testTag("moderation-preview-loading")
                    )
                }
            state.previewError?.let { failure ->
                item("preview-error") {
                    Text(
                        moderationFailureText(failure, language),
                        Modifier.testTag("moderation-preview-error"),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
            state.preview
                ?.takeIf {
                    !state.previewLoading &&
                        state.previewError == null &&
                        it.item.target == state.selected
                }
                ?.let { preview ->
                    item("preview-title") {
                        Text(
                            preview.item.title.value(language),
                            Modifier.testTag("moderation-preview-title"),
                            style = MaterialTheme.typography.headlineSmall,
                        )
                    }
                    item("preview-meta") {
                        Text(
                            "${kindText(preview.item.target.kind, language)} · ${statusText(preview.item.status, language)}\n${preview.item.createdAt}"
                        )
                    }
                    item("preview-summary") { Text(preview.item.summary.value(language)) }
                    items(preview.images, key = { "image-$it" }) { url ->
                        PublicImage(
                            url,
                            preview.item.title.value(language),
                            language,
                            Modifier.fillMaxWidth().height(220.dp),
                        )
                    }
                    item("preview-body") {
                        Text(
                            preview.body.value(language),
                            Modifier.testTag("moderation-preview-body"),
                        )
                    }
                    items(preview.fields, key = { it.key }) { field ->
                        Card(Modifier.fillMaxWidth()) {
                            Column(
                                Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    fieldLabel(field.key, language),
                                    style = MaterialTheme.typography.labelLarge,
                                )
                                // Plain text: private review links do not launch activities or
                                // public routes.
                                Text(
                                    field.text.value(language),
                                    Modifier.testTag("moderation-field-${field.key}"),
                                )
                            }
                        }
                    }
                    if (decisionContent != null) item("decision-actions") { decisionContent() }
                }
        } else {
            item("refresh") {
                OutlinedButton(actions.refresh, Modifier.testTag("moderation-refresh")) {
                    Text(tr(language, "Liste und Zugriff prüfen", "Оновити список і доступ"))
                }
            }
            item("search") {
                OutlinedTextField(
                    state.search,
                    actions.search,
                    Modifier.fillMaxWidth().testTag("moderation-search"),
                    label = {
                        Text(
                            tr(
                                language,
                                "Geladene Einträge durchsuchen",
                                "Пошук у завантажених записах",
                            )
                        )
                    },
                    singleLine = true,
                )
                Text(
                    tr(
                        language,
                        "Die Suche betrifft nur die geladenen ersten 100 Dokumente je Bereich.",
                        "Пошук охоплює лише перші 100 завантажених документів кожного розділу.",
                    )
                )
            }
            item("filters") {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(
                        { actions.filter(null) },
                        Modifier.testTag("moderation-filter-all"),
                    ) {
                        Text(tr(language, "Alle Typen", "Усі типи"))
                    }
                    state.section.kinds.forEach { kind ->
                        FilterChip(
                            state.filter == kind,
                            { actions.filter(kind) },
                            { Text(kindText(kind, language)) },
                            Modifier.testTag("moderation-filter-${kind.name}"),
                        )
                    }
                    ModerationSort.entries.forEach { sort ->
                        FilterChip(
                            state.sort == sort,
                            { actions.sort(sort) },
                            { Text(sortText(sort, language)) },
                            Modifier.testTag("moderation-sort-${sort.name}"),
                        )
                    }
                }
            }
            state.section.kinds.forEach { kind ->
                val part = state.parts[kind]
                item("status-$kind") {
                    Text(kindText(kind, language), style = MaterialTheme.typography.titleMedium)
                    if (part == null || part.loading)
                        LinearProgressIndicator(
                            Modifier.fillMaxWidth().testTag("moderation-loading-${kind.name}")
                        )
                    part?.error?.let { error ->
                        Text(
                            moderationFailureText(error, language),
                            Modifier.testTag("moderation-error-${kind.name}"),
                            color = MaterialTheme.colorScheme.error,
                        )
                        TextButton(
                            { actions.retry(kind) },
                            Modifier.testTag("moderation-retry-${kind.name}"),
                        ) {
                            Text(tr(language, "Erneut laden", "Завантажити знову"))
                        }
                    }
                    part
                        ?.head
                        ?.takeIf { !part.loading && part.error == null }
                        ?.let { head ->
                            Text(
                                tr(
                                    language,
                                    "${head.items.size} passende Einträge aus ${head.rawCount} geladenen Dokumenten.",
                                    "Відповідних записів: ${head.items.size}; завантажено документів: ${head.rawCount}.",
                                )
                            )
                            if (head.capped)
                                Text(
                                    tr(
                                        language,
                                        "Grenze von 100 Dokumenten erreicht; dies ist keine vollständige Warteschlange.",
                                        "Досягнуто межі 100 документів; це не повна черга.",
                                    ),
                                    Modifier.testTag("moderation-cap-${kind.name}"),
                                )
                        }
                }
            }
            val visible = ModerationContract.visible(state, language)
            if (
                visible.isEmpty() &&
                    state.section.kinds.all {
                        state.parts[it]?.let { p ->
                            p.head != null && !p.loading && p.error == null
                        } == true
                    }
            )
                item("empty") {
                    Text(
                        tr(
                            language,
                            "Keine passenden geladenen Einträge.",
                            "Серед завантажених записів немає відповідних.",
                        ),
                        Modifier.testTag("moderation-empty"),
                    )
                }
            items(visible, key = { "${it.target.kind}-${it.target.id}" }) { item ->
                Card(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            kindText(item.target.kind, language),
                            style = MaterialTheme.typography.labelLarge,
                        )
                        Text(
                            item.title.value(language),
                            style = MaterialTheme.typography.titleLarge,
                        )
                        Text(item.summary.value(language))
                        item.submitter?.let { Text(it) }
                        Text(item.createdAt.toString(), style = MaterialTheme.typography.bodySmall)
                        OutlinedButton(
                            { actions.open(item.target) },
                            Modifier.fillMaxWidth()
                                .testTag(
                                    "moderation-open-${item.target.kind.name}-${item.target.id}"
                                ),
                        ) {
                            Text(
                                tr(
                                    language,
                                    "Geschützte Vorschau öffnen",
                                    "Відкрити захищений перегляд",
                                )
                            )
                        }
                    }
                }
            }
            state.previewError?.let { error ->
                item("invalid-target") {
                    Text(
                        moderationFailureText(error, language),
                        Modifier.testTag("moderation-preview-error"),
                    )
                }
            }
        }
    }
}

fun moderationFailureText(failure: ModerationFailure, language: String): String =
    when (failure) {
        ModerationFailure.SIGN_IN ->
            tr(
                language,
                "Bitte mit einem berechtigten Konto anmelden.",
                "Увійдіть до акаунта з відповідними правами.",
            )
        ModerationFailure.NOT_READY ->
            tr(
                language,
                "Zugriff erst nach bestätigtem Konto, aktiver TOTP-Sitzung und allen Freigaben.",
                "Доступ можливий лише після підтвердження акаунта, активної TOTP-сесії та всіх перевірок.",
            )
        ModerationFailure.DENIED ->
            tr(
                language,
                "Nur Plattform-Owner und App Admin haben Zugriff. Organisationsrollen reichen nicht aus.",
                "Доступ мають лише власник платформи та адміністратор застосунку. Ролі в організації недостатньо.",
            )
        ModerationFailure.OFFLINE ->
            tr(
                language,
                "Server nicht erreichbar. Gespeicherte Vorschauen werden nicht als aktuell angezeigt.",
                "Сервер недоступний. Збережені перегляди не показуються як актуальні.",
            )
        ModerationFailure.INDEX ->
            tr(
                language,
                "Die Serverabfrage ist noch nicht verfügbar. Keine vollständige Liste bestätigt.",
                "Серверний запит поки недоступний. Повноту списку не підтверджено.",
            )
        ModerationFailure.INVALID ->
            tr(
                language,
                "Dieser Datensatz kann nicht sicher angezeigt werden.",
                "Цей запис неможливо безпечно показати.",
            )
        ModerationFailure.MISSING ->
            tr(language, "Der Eintrag ist nicht mehr verfügbar.", "Запис більше недоступний.")
        ModerationFailure.STALE ->
            tr(
                language,
                "Die Daten ändern sich gerade. Bitte erneut prüfen.",
                "Дані зараз змінюються. Перевірте знову.",
            )
        ModerationFailure.UNKNOWN ->
            tr(
                language,
                "Laden fehlgeschlagen. Bitte erneut prüfen.",
                "Не вдалося завантажити. Перевірте знову.",
            )
    }

private fun kindText(kind: ModerationKind, language: String) =
    when (kind) {
        ModerationKind.NEWS -> tr(language, "Nachrichten", "Новини")
        ModerationKind.EVENT -> tr(language, "Veranstaltungen", "Події")
        ModerationKind.ORGANIZATION -> tr(language, "Organisationsanträge", "Заявки організацій")
    }

private fun sortText(sort: ModerationSort, language: String) =
    when (sort) {
        ModerationSort.NEWEST -> tr(language, "Neueste zuerst", "Спочатку нові")
        ModerationSort.OLDEST -> tr(language, "Älteste zuerst", "Спочатку давні")
        ModerationSort.NAME_ASCENDING -> tr(language, "Name: A–Z", "Назва: А–Я")
        ModerationSort.NAME_DESCENDING -> tr(language, "Name: Z–A", "Назва: Я–А")
    }

private fun statusText(status: String, language: String) =
    when (status) {
        "pendingReview" -> tr(language, "In Prüfung", "На перевірці")
        "needsRevision" -> tr(language, "Überarbeitung erforderlich", "Потребує доопрацювання")
        "rejected" -> tr(language, "Abgelehnt", "Відхилено")
        "approved" -> tr(language, "Genehmigt", "Схвалено")
        "draft" -> tr(language, "Entwurf", "Чернетка")
        "archived" -> tr(language, "Archiviert", "Архівовано")
        else -> tr(language, "Nicht mehr verfügbar", "Більше недоступно")
    }

private fun fieldLabel(key: String, language: String): String {
    val labels =
        mapOf(
            "submittedByUserId" to ("Antragstellendes Konto" to "Акаунт заявника"),
            "submittedAt" to ("Eingereicht am" to "Подано"),
            "reviewMessage" to ("Überarbeitungshinweis" to "Зауваження"),
            "rejectionReason" to ("Ablehnungsgrund" to "Причина відмови"),
            "reviewedByUserId" to ("Geprüft durch" to "Перевірено"),
            "reviewedAt" to ("Prüfdatum" to "Дата перевірки"),
            "organizationType" to ("Organisationstyp" to "Тип організації"),
            "profileKind" to ("Profilart" to "Вид профілю"),
            "city" to ("Stadt" to "Місто"),
            "federalState" to ("Bundesland" to "Федеральна земля"),
            "address" to ("Adresse" to "Адреса"),
            "contactPerson" to ("Kontaktperson" to "Контактна особа"),
            "email" to ("E-Mail" to "Електронна пошта"),
            "contactEmail" to ("Kontakt-E-Mail" to "Контактна пошта"),
            "phone" to ("Telefon" to "Телефон"),
            "contactPhone" to ("Kontakttelefon" to "Контактний телефон"),
            "website" to ("Webseite" to "Вебсайт"),
            "missionStatement" to ("Ziel und Auftrag" to "Мета та місія"),
            "languages" to ("Sprachen" to "Мови"),
            "foundedYear" to ("Gründungsjahr" to "Рік заснування"),
            "foundedMonth" to ("Gründungsmonat" to "Місяць заснування"),
            "donationURL" to ("Spendenlink" to "Посилання для пожертв"),
            "organizationName" to ("Organisation" to "Організація"),
            "authorName" to ("Autor" to "Автор"),
            "publishedAt" to ("Veröffentlicht am" to "Опубліковано"),
            "scheduledAt" to ("Geplante Veröffentlichung" to "Запланована публікація"),
            "sourceName" to ("Quelle" to "Джерело"),
            "sourceURL" to ("Quellenlink" to "Посилання на джерело"),
            "category" to ("Kategorie" to "Категорія"),
            "additionalCategories" to ("Weitere Kategorien" to "Інші категорії"),
            "secondaryCategories" to ("Weitere Kategorien" to "Інші категорії"),
            "tags" to ("Schlagwörter" to "Теги"),
            "regionScope" to ("Region" to "Регіон"),
            "venue" to ("Veranstaltungsort" to "Місце проведення"),
            "locationNote" to ("Hinweis zum Ort" to "Примітка про місце"),
            "organizerName" to ("Veranstalter" to "Організатор"),
            "organizerURL" to ("Veranstalterlink" to "Посилання організатора"),
            "contactURL" to ("Kontaktlink" to "Контактне посилання"),
            "startDate" to ("Beginn" to "Початок"),
            "endDate" to ("Ende" to "Завершення"),
            "participationMode" to ("Teilnahmeart" to "Спосіб участі"),
            "capacity" to ("Plätze" to "Місця"),
            "price" to ("Preis" to "Ціна"),
            "audience" to ("Zielgruppe" to "Аудиторія"),
            "minimumAge" to ("Mindestalter" to "Мінімальний вік"),
            "maximumAge" to ("Höchstalter" to "Максимальний вік"),
            "cancelledAt" to ("Abgesagt am" to "Скасовано"),
            "cancellationReason" to ("Absagegrund" to "Причина скасування"),
            "serviceModes" to ("Leistungsarten" to "Види послуг"),
            "serviceArea" to ("Einzugsgebiet" to "Територія роботи"),
            "services" to ("Leistungen" to "Послуги"),
            "specialHoursNote" to ("Hinweis zu Öffnungszeiten" to "Примітка про години роботи"),
            "orderURL" to ("Bestelllink" to "Посилання для замовлення"),
            "bookingURL" to ("Buchungslink" to "Посилання для бронювання"),
            "currentOfferTitle" to ("Aktuelles Angebot" to "Поточна пропозиція"),
            "currentOfferDetails" to ("Angebotsdetails" to "Деталі пропозиції"),
            "currentOfferURL" to ("Angebotslink" to "Посилання на пропозицію"),
            "currentOfferValidUntil" to ("Angebot gültig bis" to "Пропозиція діє до"),
            "externalAction" to ("Externe Aktion" to "Зовнішня дія"),
            "pricing.kind" to ("Preisart" to "Тип ціни"),
            "pricing.amount" to ("Betrag" to "Сума"),
            "pricing.maximumAmount" to ("Höchstbetrag" to "Максимальна сума"),
            "pricing.currencyCode" to ("Währung" to "Валюта"),
            "pricing.note" to ("Preishinweis" to "Примітка про ціну"),
        )
    labels[key]?.let {
        return tr(language, it.first, it.second)
    }
    if (key.startsWith("occurrence."))
        return tr(language, "Termin ${key.substringAfter('.')}", "Дата ${key.substringAfter('.')}")
    if (key.startsWith("hours.")) {
        val days =
            mapOf(
                "monday" to ("Montag" to "Понеділок"),
                "tuesday" to ("Dienstag" to "Вівторок"),
                "wednesday" to ("Mittwoch" to "Середа"),
                "thursday" to ("Donnerstag" to "Четвер"),
                "friday" to ("Freitag" to "П’ятниця"),
                "saturday" to ("Samstag" to "Субота"),
                "sunday" to ("Sonntag" to "Неділя"),
            )
        days[key.substringAfter('.')]?.let {
            return tr(language, it.first, it.second)
        }
    }
    return key.removeSuffix("URL")
}
