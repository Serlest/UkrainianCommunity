package at.uac.android.feature.browse

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import java.text.NumberFormat
import java.time.Instant
import java.util.Currency
import java.util.Locale

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
        if (content.kind == ContentKind.ORGANIZATIONS)
            f.string("coverURL").ifEmpty { f.string("imageURL") }
        else f.string("imageURL")
    Column(
        Modifier.widthIn(max = 760.dp).fillMaxWidth().testTag("detail-content"),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Heading(content.title(l))
        Text(content.kind.label(l) + " · " + label(content.category, l))
        PublicImage(
            image,
            f.map("mediaMetadata").string("alternativeText").ifEmpty { content.title(l) },
            l,
        )
        for (field in listOf("caption", "credit")) f.map("mediaMetadata")
            .string(field)
            .takeIf(String::isNotBlank)
            ?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
        SelectionContainer {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(content.summary(l), style = MaterialTheme.typography.titleMedium)
                Text(content.body(l))
            }
        }
        Text(displayTime(content.publishedAt, l))
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
            if (source.isNotEmpty()) Text(tr(l, "Quelle: ", "Джерело: ") + source)
            SafeLink(tr(l, "Originalquelle", "Першоджерело"), f.string("sourceURL"), l)
            val action = f.map("externalAction")
            SafeLink(
                action.string("title").ifEmpty {
                    tr(l, "Weitere Informationen", "Дізнатися більше")
                },
                action.string("url"),
                l,
            )
        }
        val tags = f.strings("tags")
        if (tags.isNotEmpty()) Text(tags.joinToString(" ") { "#$it" })
        Section(tr(l, "Aktionen mit Konto", "Дії з акаунтом")) {
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
        TextButton(model::refresh, Modifier.testTag("detail-refresh")) {
            Text(tr(l, "Aktualisieren", "Оновити"))
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
    Section(tr(language, "Termin und Teilnahme", "Час та участь")) {
        val cancelled = f.string("cancellationState") == "cancelled"
        val past = f.time("endDate")!! < Instant.now()
        if (cancelled)
            Text(tr(language, "Abgesagt", "Скасовано"), color = MaterialTheme.colorScheme.error)
        Text(
            displayTime(f.time("startDate")!!, language, f["isAllDay"] == true) +
                " — " +
                displayTime(f.time("endDate")!!, language, f["isAllDay"] == true)
        )
        Text(
            tr(
                language,
                "Anzeige in der Zeitzone dieses Geräts.",
                "Час показано в часовому поясі пристрою.",
            )
        )
        val occurrences = (f["occurrences"] as? List<*>)?.filterIsInstance<Map<*, *>>().orEmpty()
        occurrences.forEach { raw ->
            val start = raw["startDate"] as? Instant
            val end = raw["endDate"] as? Instant
            if (start != null && end != null && end >= start) {
                Text(
                    (if (raw["status"] == "cancelled") tr(language, "Abgesagt · ", "Скасовано · ")
                    else "") +
                        (if (raw["isAllDay"] == true) tr(language, "Ganztägig · ", "Увесь день · ")
                        else "") +
                        displayTime(start, language, raw["isAllDay"] == true) +
                        " — " +
                        displayTime(end, language, raw["isAllDay"] == true)
                )
            } else Text(tr(language, "Ungültiger Einzeltermin", "Некоректний час окремої події"))
        }
        Text(priceText(f, language))
        f.map("pricing").string("note").takeIf(String::isNotEmpty)?.let { Text(it) }
        val capacity = f.count("capacity")
        val registered = f.count("registeredCount")
        if (capacity > 0)
            Text(
                tr(
                    language,
                    "Angemeldet: $registered / $capacity",
                    "Зареєстровано: $registered / $capacity",
                )
            )
        if (capacity > 0 && registered >= capacity) Text(tr(language, "Ausgebucht", "Місць немає"))
        f.string("audience").takeIf(String::isNotEmpty)?.let {
            Text(tr(language, "Für: ", "Для: ") + label(it, language))
        }
        if (past) Text(tr(language, "Diese Veranstaltung ist vorbei.", "Ця подія вже завершилася."))
        val mode =
            f.string("participationMode").ifEmpty {
                if (f["requiresRegistration"] == true) "inAppRegistration" else "none"
            }
        when (mode) {
            "none" -> Text(tr(language, "Keine Anmeldung erforderlich", "Реєстрація не потрібна"))
            "inAppRegistration" ->
                Text(
                    tr(
                        language,
                        "Anmeldung im Bereich „Meine Teilnahme“ weiter unten.",
                        "Реєстрація — у розділі «Моя участь» нижче.",
                    )
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
        Text(
            listOf("venue", "city", "locationNote", "organizerName")
                .map(f::string)
                .filter(String::isNotBlank)
                .joinToString(" · ")
        )
        ContactActions(f, language)
        SafeLink(tr(language, "Veranstalter", "Організатор"), f.string("organizerURL"), language)
        SafeLink(tr(language, "Kontakt", "Контакт"), f.string("contactURL"), language)
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
        PublicImage(f.string("logoURL"), content.title(l), l)
        localized("missionStatement").takeIf(String::isNotBlank)?.let { Text(it) }
        Text(
            listOf(f.string("city"), f.strings("languages").joinToString(" / "))
                .filter(String::isNotBlank)
                .joinToString(" · ")
        )
        if (f.count("foundedYear") > 0)
            Text(tr(l, "Gegründet: ", "Засновано: ") + f.count("foundedYear"))
        Text(tr(l, "Abonnements: ", "Підписників: ") + f.count("subscriberCount"))
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
