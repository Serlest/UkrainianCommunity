package at.uac.android.feature.browse

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.design.UacCard
import at.uac.android.design.UacDesign
import java.text.NumberFormat
import java.time.Instant
import java.util.Currency
import java.util.Locale

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ContentDetail(
    content: Content,
    s: BrowseState,
    model: BrowseViewModel,
    personalActions: (@Composable (Content, BrowseState) -> Unit)? = null,
    publicGallery: (@Composable (Content, BrowseState) -> Unit)? = null,
) {
    val l = s.language
    val f = content.fields
    val image =
        if (content.kind == ContentKind.ORGANIZATIONS) organizationImageUrl(f, preferCover = true)
        else f.string("imageURL")
    Column(
        Modifier.widthIn(max = 760.dp).fillMaxWidth().testTag("detail-content"),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Surface(
            shape = RoundedCornerShape(22.dp),
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            tonalElevation = 1.dp,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (image.isNotBlank() || content.kind == ContentKind.ORGANIZATIONS) {
                    val fallback =
                        when (content.kind) {
                            ContentKind.NEWS -> at.uac.android.design.UacIcon.NEWS
                            ContentKind.EVENTS -> at.uac.android.design.UacIcon.CALENDAR
                            ContentKind.ORGANIZATIONS -> at.uac.android.design.UacIcon.ORGANIZATIONS
                        }
                    PublicImage(
                        image,
                        f.map("mediaMetadata").string("alternativeText").ifEmpty {
                            content.title(l)
                        },
                        l,
                        Modifier.fillMaxWidth()
                            .aspectRatio(16f / 9f)
                            .clip(RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)),
                        fallback = fallback,
                        presentation =
                            if (
                                content.kind == ContentKind.ORGANIZATIONS &&
                                    f.string("coverURL").isBlank()
                            )
                                PublicImagePresentation.VIEWPORT_FIT
                            else PublicImagePresentation.VIEWPORT_CROP,
                    )
                }
                Column(
                    Modifier.padding(start = 18.dp, end = 18.dp, bottom = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Surface(
                        shape = RoundedCornerShape(10.dp),
                        color = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ) {
                        Text(
                            content.kind.label(l) + " · " + label(content.category, l),
                            Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                    Heading(content.title(l))
                    Text(
                        displayTime(content.publishedAt, l),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    val credits =
                        listOf("caption", "credit")
                            .map { f.map("mediaMetadata").string(it) }
                            .filter(String::isNotBlank)
                            .joinToString(" · ")
                    if (credits.isNotBlank())
                        Text(
                            credits,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                }
            }
        }
        if (content.summary(l).isNotBlank() || content.body(l).isNotBlank()) {
            UacCard {
                SelectionContainer {
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        content.summary(l).takeIf(String::isNotBlank)?.let {
                            Text(it, style = MaterialTheme.typography.titleMedium)
                        }
                        content.body(l).takeIf(String::isNotBlank)?.let {
                            Text(it, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
        }
        if (content.kind == ContentKind.EVENTS) EventInformation(content, l)
        if (content.kind == ContentKind.ORGANIZATIONS)
            OrganizationInformation(content, s, model, publicGallery)
        else {
            val orgId = f.string("organizationId")
            if (orgId.isNotEmpty() && '/' !in orgId)
                TextButton(
                    { model.navigate("organizations/$orgId") },
                    Modifier.testTag("source-organization"),
                ) {
                    Text(
                        f.string("organizationName").ifEmpty {
                            tr(l, "Organisation ansehen", "Переглянути організацію")
                        }
                    )
                }
        }
        if (content.kind == ContentKind.NEWS) {
            val source = f.string("sourceName")
            val action = f.map("externalAction")
            if (
                source.isNotBlank() ||
                    f.string("sourceURL").isNotBlank() ||
                    action.string("url").isNotBlank()
            ) {
                Section(tr(l, "Quelle und Links", "Джерело та посилання")) {
                    if (source.isNotBlank())
                        Text(source, style = MaterialTheme.typography.titleMedium)
                    SafeLink(tr(l, "Originalquelle", "Першоджерело"), f.string("sourceURL"), l)
                    SafeLink(
                        action.string("title").ifEmpty {
                            tr(l, "Weitere Informationen", "Дізнатися більше")
                        },
                        action.string("url"),
                        l,
                    )
                }
            }
        }
        val tags = f.strings("tags").filter(String::isNotBlank)
        if (tags.isNotEmpty())
            UacCard {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    tags.forEach { tag ->
                        Surface(
                            color = MaterialTheme.colorScheme.primaryContainer,
                            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Text(
                                "#$tag",
                                Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.labelLarge,
                            )
                        }
                    }
                }
            }
        Section(tr(l, "Aktionen", "Дії")) {
            if (personalActions != null) personalActions(content, s)
            else
                TextButton({ model.navigate("profile") }) {
                    Text(tr(l, "Zum Kontobereich", "До розділу акаунта"))
                }
        }
        if (s.data.related.isNotEmpty()) {
            Heading(tr(l, "Ähnliche Inhalte", "Схожі матеріали"))
            s.data.related.forEach { item ->
                ContentCard(item, l) { model.navigate("${item.kind.collection}/${item.id}") }
            }
        }
    }
}

fun priceText(fields: Fields, language: String): String {
    val pricing = fields.map("pricing")
    val code = pricing.string("currencyCode").ifBlank { "EUR" }.uppercase(Locale.ROOT)
    fun money(value: Any?): String? =
        (value as? Number)
            ?.toDouble()
            ?.takeIf { it.isFinite() && it >= 0 }
            ?.let { amount ->
                runCatching {
                    NumberFormat.getCurrencyInstance(Locale.forLanguageTag(language))
                        .apply { currency = Currency.getInstance(code) }
                        .format(amount)
                }
                    .getOrElse { "$amount $code" }
            }
    val amount = money(pricing["amount"])
    return when (pricing.string("kind")) {
        "free" -> tr(language, "Kostenlos", "Безкоштовно")
        "exact" -> amount
        "startingFrom" -> amount?.let { tr(language, "Ab ", "Від ") + it }
        "range" -> amount?.let { low -> money(pricing["maximumAmount"])?.let { "$low – $it" } }
        else -> money(fields["price"])
    } ?: tr(language, "Preis nicht angegeben", "Ціну не зазначено")
}

@Composable
private fun EventInformation(content: Content, language: String) {
    val f = content.fields
    val start = f.time("startDate")
    val end = f.time("endDate")
    val allDay = f["isAllDay"] == true
    val cancelled = f.string("cancellationState") == "cancelled"
    val past = end?.let { it < Instant.now() } == true
    Section(tr(language, "Auf einen Blick", "Коротко про подію")) {
        if (cancelled)
            Surface(
                color = MaterialTheme.colorScheme.errorContainer,
                contentColor = MaterialTheme.colorScheme.onErrorContainer,
                shape = RoundedCornerShape(10.dp),
            ) {
                Text(
                    tr(language, "Abgesagt", "Скасовано"),
                    Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        if (start != null && end != null)
            DetailFact(
                tr(language, "Wann", "Коли"),
                displayTime(start, language, allDay) + " – " + displayTime(end, language, allDay),
            )
        val place =
            listOf("venue", "city", "locationNote")
                .map(f::string)
                .filter(String::isNotBlank)
                .joinToString(" · ")
        if (place.isNotBlank()) DetailFact(tr(language, "Wo", "Де"), place)
        DetailFact(tr(language, "Preis", "Вартість"), priceText(f, language))
        f.map("pricing").string("note").takeIf(String::isNotEmpty)?.let {
            Text(it, style = MaterialTheme.typography.bodySmall)
        }
        f.string("audience").takeIf(String::isNotEmpty)?.let {
            DetailFact(tr(language, "Für wen", "Для кого"), label(it, language))
        }
        f.string("organizerName").takeIf(String::isNotBlank)?.let {
            DetailFact(tr(language, "Veranstalter", "Організатор"), it)
        }
        Text(
            tr(
                language,
                "Zeitangaben entsprechen der Zeitzone dieses Geräts.",
                "Час показано відповідно до часового поясу пристрою.",
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    val occurrences = (f["occurrences"] as? List<*>)?.filterIsInstance<Map<*, *>>().orEmpty()
    if (occurrences.isNotEmpty())
        Section(tr(language, "Weitere Termine", "Інші дати")) {
            val occurrences =
                (f["occurrences"] as? List<*>)?.filterIsInstance<Map<*, *>>().orEmpty()
            occurrences.forEach { raw ->
                val start = raw["startDate"] as? Instant
                val end = raw["endDate"] as? Instant
                if (start != null && end != null && end >= start) {
                    Text(
                        (if (raw["status"] == "cancelled")
                            tr(language, "Abgesagt · ", "Скасовано · ")
                        else "") +
                            (if (raw["isAllDay"] == true)
                                tr(language, "Ganztägig · ", "Увесь день · ")
                            else "") +
                            displayTime(start, language, raw["isAllDay"] == true) +
                            " — " +
                            displayTime(end, language, raw["isAllDay"] == true)
                    )
                } else
                    Text(tr(language, "Ungültiger Einzeltermin", "Некоректний час окремої події"))
            }
        }
    Section(tr(language, "Teilnahme", "Участь")) {
        val capacity = f.count("capacity")
        val registered = f.count("registeredCount")
        if (capacity > 0)
            DetailFact(
                tr(language, "Plätze", "Місця"),
                tr(
                    language,
                    "$registered von $capacity angemeldet",
                    "Зареєстровано $registered із $capacity",
                ),
            )
        if (capacity > 0 && registered >= capacity)
            Text(tr(language, "Ausgebucht", "Місць немає"), color = MaterialTheme.colorScheme.error)
        if (past)
            Text(
                tr(language, "Diese Veranstaltung ist vorbei.", "Ця подія вже завершилася."),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        val mode =
            f.string("participationMode").ifEmpty {
                if (f["requiresRegistration"] == true) "inAppRegistration" else "none"
            }
        when (mode) {
            "none" ->
                DetailFact(
                    tr(language, "Anmeldung", "Реєстрація"),
                    tr(language, "Nicht erforderlich", "Не потрібна"),
                )
            "inAppRegistration" ->
                DetailFact(
                    tr(language, "Anmeldung", "Реєстрація"),
                    tr(
                        language,
                        "Anmeldung im Bereich „Meine Teilnahme“ weiter unten.",
                        "Реєстрація — у розділі «Моя участь» нижче.",
                    ),
                )
            "externalRegistration",
            "externalTickets" ->
                if (!cancelled && !past) {
                    SafeLink(
                        tr(language, "Externe Anmeldung / Tickets", "Зовнішня реєстрація / квитки"),
                        f.map("externalAction").string("url"),
                        language,
                    )
                }
            else ->
                Text(
                    tr(language, "Teilnahmeart nicht unterstützt", "Спосіб участі не підтримується")
                )
        }
        ContactActions(f, language)
        SafeLink(tr(language, "Veranstalter", "Організатор"), f.string("organizerURL"), language)
        SafeLink(tr(language, "Kontakt", "Контакт"), f.string("contactURL"), language)
    }
}

@Composable
private fun DetailFact(label: String, value: String) {
    if (value.isBlank()) return
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun OrganizationInformation(
    content: Content,
    s: BrowseState,
    model: BrowseViewModel,
    publicGallery: (@Composable (Content, BrowseState) -> Unit)?,
) {
    val l = s.language
    val f = content.fields
    val directory = f.map("directoryProfile")
    fun localized(key: String) =
        content.localization(l).string(key).ifBlank {
            directory.string(key).ifBlank { f.string(key) }
        }
    Section(tr(l, "Über die Organisation", "Про організацію")) {
        val logo = organizationImageUrl(f, preferCover = false)
        val hero = organizationImageUrl(f, preferCover = true)
        if (logo.isNotBlank() && logo != hero) PublicImage(logo, content.title(l), l)
        localized("missionStatement").takeIf(String::isNotBlank)?.let { Text(it) }
        DetailFact(tr(l, "Ort", "Місто"), f.string("city"))
        DetailFact(
            tr(l, "Sprachen", "Мови"),
            f.strings("languages").joinToString(" / "),
        )
        if (f.count("foundedYear") > 0)
            DetailFact(
                tr(l, "Gegründet", "Засновано"),
                f.count("foundedYear").toString(),
            )
        DetailFact(
            tr(l, "Abonnements", "Підписників"),
            f.count("subscriberCount").toString(),
        )
        ContactActions(f, l)
        listOf(
                "website" to tr(l, "Website", "Вебсайт"),
                "donationURL" to tr(l, "Unterstützen", "Підтримати"),
                "telegramURL" to "Telegram",
                "facebookURL" to "Facebook",
                "instagramURL" to "Instagram",
                "youtubeURL" to "YouTube",
                "linkedinURL" to "LinkedIn",
                "whatsappURL" to "WhatsApp",
            )
            .forEach { (key, title) -> SafeLink(title, f.string(key), l) }
        f.map("socialLinks").forEach { (key, value) ->
            if (value is String) SafeLink(key, value, l)
        }
    }
    if (directory.isNotEmpty())
        Section(tr(l, "Angebot und Öffnungszeiten", "Послуги та години роботи")) {
            Text(label(directory.string("profileKind"), l))
            Text(directory.strings("serviceModes").joinToString(" · ") { label(it, l) })
            localized("serviceArea").takeIf(String::isNotBlank)?.let { Text(it) }
            content
                .localization(l)
                .strings("services")
                .ifEmpty { directory.strings("services") }
                .forEach { Text("• $it") }
            listOf("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
                .forEach { day ->
                    directory.map("regularHours").string(day).takeIf(String::isNotEmpty)?.let {
                        Text(
                            label(day, l) +
                                ": " +
                                if (it == "closed") tr(l, "Geschlossen", "Зачинено") else it
                        )
                    }
                }
            localized("specialHoursNote").takeIf(String::isNotBlank)?.let { Text(it) }
            SafeLink(tr(l, "Bestellen", "Замовити"), directory.string("orderURL"), l)
            SafeLink(tr(l, "Buchen", "Забронювати"), directory.string("bookingURL"), l)
            if (directory.time("currentOfferValidUntil")?.let { it >= Instant.now() } != false) {
                localized("currentOfferTitle").takeIf(String::isNotBlank)?.let {
                    Text(it, style = MaterialTheme.typography.titleMedium)
                }
                localized("currentOfferDetails").takeIf(String::isNotBlank)?.let { Text(it) }
                SafeLink(
                    tr(l, "Zum Angebot", "До пропозиції"),
                    directory.string("currentOfferURL"),
                    l,
                )
            }
        }
    if (publicGallery != null) publicGallery(content, s)
    else if (s.data.photos.isNotEmpty())
        Section(tr(l, "Fotos", "Фото")) {
            s.data.photos.forEach { photo ->
                PublicImage(
                    photo.fields.string("imageURL"),
                    photo.fields.string("caption").ifBlank { content.title(l) },
                    l,
                )
                Text(photo.fields.string("caption"))
            }
        }
    if (s.data.profiles.isNotEmpty())
        Section(tr(l, "Öffentliches Team", "Публічна команда")) {
            s.data.profiles.forEach { profile ->
                Text(
                    profile.fields.string("displayName").ifBlank {
                        tr(l, "Profil nicht verfügbar", "Профіль недоступний")
                    },
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(profile.fields.string("city"))
            }
        }
    Section(tr(l, "Inhalte dieser Organisation", "Матеріали організації")) {
        TextButton(
            { model.navigate("news:${content.id}") },
            Modifier.testTag("organization-news"),
        ) {
            Text(ContentKind.NEWS.label(l))
        }
        TextButton(
            { model.navigate("events:${content.id}") },
            Modifier.testTag("organization-events"),
        ) {
            Text(ContentKind.EVENTS.label(l))
        }
    }
}

@Composable
private fun ContactActions(fields: Fields, language: String) {
    val context = LocalContext.current
    var pending by remember { mutableStateOf<Pair<String, String>?>(null) }
    var failed by remember { mutableStateOf(false) }
    fun action(value: String, scheme: String): Pair<String, String>? =
        value.takeIf(String::isNotBlank)?.let { value to (scheme + Uri.encode(value)) }
    val address = fields.string("address")
    val phone = fields.string("contactPhone").ifBlank { fields.string("phone") }
    val email = fields.string("contactEmail").ifBlank { fields.string("email") }
    val actions =
        listOfNotNull(
            action(address, "geo:0,0?q="),
            action(phone.takeIf { it.matches(Regex("[+0-9 ()-]{3,30}")) }.orEmpty(), "tel:"),
            action(
                email.takeIf { it.matches(Regex("[^\\s@]+@[^\\s@]+\\.[^\\s@]+")) }.orEmpty(),
                "mailto:",
            ),
        )
    actions.forEach { entry ->
        TextButton({
            failed = false
            pending = entry
        }) {
            Text(entry.first)
        }
    }
    pending?.let { entry ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text(tr(language, "Externe App", "Зовнішній застосунок")) },
            text = {
                Column {
                    Text(entry.first)
                    Text(
                        tr(
                            language,
                            "Testdaten – keine echten Kontaktdaten.",
                            "Тестові дані — не справжні контакти.",
                        )
                    )
                    if (failed)
                        Text(
                            tr(
                                language,
                                "Keine passende App gefunden.",
                                "Відповідного застосунку немає.",
                            )
                        )
                }
            },
            confirmButton = {
                TextButton({
                    val intent =
                        Intent(
                            if (entry.second.startsWith("tel:")) Intent.ACTION_DIAL
                            else if (entry.second.startsWith("mailto:")) Intent.ACTION_SENDTO
                            else Intent.ACTION_VIEW,
                            Uri.parse(entry.second),
                        )
                    failed = runCatching { context.startActivity(intent) }.isFailure
                    if (!failed) pending = null
                }) {
                    Text(tr(language, "Öffnen", "Відкрити"))
                }
            },
            dismissButton = {
                FlowRow {
                    TextButton({
                        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                            .setPrimaryClip(ClipData.newPlainText("UAC", entry.first))
                    }) {
                        Text(tr(language, "Kopieren", "Копіювати"))
                    }
                    TextButton({ pending = null }) { Text(tr(language, "Abbrechen", "Скасувати")) }
                }
            },
        )
    }
}
