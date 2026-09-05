package at.uac.android.feature.organization

import at.uac.android.feature.auth.AuthValidation
import at.uac.android.feature.browse.label
import at.uac.android.feature.browse.regions

enum class OrganizationFormField(val tag: String) {
    NAME("organization-name"),
    SUMMARY("organization-summary"),
    DETAILS("organization-details"),
    REGION("organization-region"),
    CITY("organization-city"),
    PROFILE_KIND("organization-profile-kind"),
    EMAIL("organization-email"),
    PHONE("organization-phone"),
    WEBSITE("organization-website"),
    ADDRESS("organization-address"),
    GERMAN_NAME("organization-de-name"),
    GERMAN_SUMMARY("organization-de-summary"),
    GERMAN_DETAILS("organization-de-details"),
    FORM("organization-form"),
}

enum class OrganizationFormIssue {
    NAME,
    SUMMARY,
    DETAILS,
    REGION,
    CITY,
    PROFILE_KIND,
    EMAIL,
    PHONE,
    WEBSITE,
    ADDRESS,
    GERMAN_NAME,
    GERMAN_SUMMARY,
    GERMAN_DETAILS,
    FORM,
}

/** Presentation only: the existing contract remains the authoritative submit validator. */
fun organizationFormIssues(
    draft: OrganizationDraft
): Map<OrganizationFormField, OrganizationFormIssue> {
    val issues = linkedMapOf<OrganizationFormField, OrganizationFormIssue>()
    fun check(field: OrganizationFormField, invalid: Boolean, issue: OrganizationFormIssue) {
        if (invalid) issues[field] = issue
    }
    fun points(value: String): Int = value.trim().let { it.codePointCount(0, it.length) }
    check(
        OrganizationFormField.NAME,
        draft.name.trim().length !in 1..180,
        OrganizationFormIssue.NAME,
    )
    check(
        OrganizationFormField.SUMMARY,
        points(draft.summary) !in 20..160,
        OrganizationFormIssue.SUMMARY,
    )
    check(
        OrganizationFormField.DETAILS,
        points(draft.details) > 1200,
        OrganizationFormIssue.DETAILS,
    )
    check(
        OrganizationFormField.REGION,
        draft.region !in AuthValidation.regions,
        OrganizationFormIssue.REGION,
    )
    check(
        OrganizationFormField.CITY,
        draft.city.trim().length !in 1..160,
        OrganizationFormIssue.CITY,
    )
    check(
        OrganizationFormField.PROFILE_KIND,
        draft.profileKind !in OrganizationContract.profileKinds,
        OrganizationFormIssue.PROFILE_KIND,
    )
    val email = draft.email.trim()
    check(
        OrganizationFormField.EMAIL,
        email.length > 320 ||
            (email.isNotEmpty() && (!email.contains('@') || email.any(Char::isWhitespace))),
        OrganizationFormIssue.EMAIL,
    )
    check(OrganizationFormField.PHONE, draft.phone.trim().length > 80, OrganizationFormIssue.PHONE)
    check(
        OrganizationFormField.WEBSITE,
        runCatching { OrganizationContract.website(draft.website) }.isFailure,
        OrganizationFormIssue.WEBSITE,
    )
    check(
        OrganizationFormField.ADDRESS,
        draft.address.trim().length > 500,
        OrganizationFormIssue.ADDRESS,
    )
    check(
        OrganizationFormField.GERMAN_NAME,
        draft.germanName.trim().length > 180,
        OrganizationFormIssue.GERMAN_NAME,
    )
    check(
        OrganizationFormField.GERMAN_SUMMARY,
        points(draft.germanSummary) > 160,
        OrganizationFormIssue.GERMAN_SUMMARY,
    )
    check(
        OrganizationFormField.GERMAN_DETAILS,
        points(draft.germanDetails) > 1200,
        OrganizationFormIssue.GERMAN_DETAILS,
    )
    // Unknown/hidden identity constraints must never silently become a valid form.
    if (issues.isEmpty() && runCatching { OrganizationContract.validate(draft) }.isFailure) {
        issues[OrganizationFormField.FORM] = OrganizationFormIssue.FORM
    }
    return issues
}

fun organizationRegionLabel(value: String, language: String): String {
    val labels = regions.firstOrNull { it.first == value }?.second?.split(" / ", limit = 2)
    return labels?.let { if (language == "de") it.first() else it.last() }
        ?: organizationUnknownChoice(value, language)
}

fun organizationProfileKindLabel(value: String, language: String): String =
    if (value in OrganizationContract.profileKinds) label(value, language)
    else organizationUnknownChoice(value, language)

private fun organizationUnknownChoice(value: String, language: String): String =
    if (value.isEmpty()) formText(language, "Bitte auswählen", "Оберіть значення")
    else formText(language, "Ungültige Auswahl", "Некоректне значення")

fun organizationFormIssueText(issue: OrganizationFormIssue, language: String): String =
    when (issue) {
        OrganizationFormIssue.NAME ->
            formText(language, "Name: 1–180 Zeichen eingeben.", "Назва: введіть 1–180 символів.")
        OrganizationFormIssue.SUMMARY ->
            formText(
                language,
                "Kurzbeschreibung: 20–160 Zeichen eingeben.",
                "Короткий опис: введіть 20–160 символів.",
            )
        OrganizationFormIssue.DETAILS ->
            formText(
                language,
                "Beschreibung: höchstens 1200 Zeichen.",
                "Повний опис: не більше 1200 символів.",
            )
        OrganizationFormIssue.REGION ->
            formText(
                language,
                "Ein gültiges Bundesland auswählen.",
                "Оберіть коректну федеральну землю.",
            )
        OrganizationFormIssue.CITY ->
            formText(language, "Ort: 1–160 Zeichen eingeben.", "Місто: введіть 1–160 символів.")
        OrganizationFormIssue.PROFILE_KIND ->
            formText(
                language,
                "Eine gültige Profilart auswählen.",
                "Оберіть коректний тип профілю.",
            )
        OrganizationFormIssue.EMAIL ->
            formText(
                language,
                "E-Mail: @, keine Leerzeichen und höchstens 320 Zeichen; oder leer lassen.",
                "Email: потрібен @, без пробілів, не більше 320 символів; або залиште порожнім.",
            )
        OrganizationFormIssue.PHONE ->
            formText(language, "Telefon: höchstens 80 Zeichen.", "Телефон: не більше 80 символів.")
        OrganizationFormIssue.WEBSITE ->
            formText(
                language,
                "Website: eine gültige HTTP-/HTTPS-Adresse ohne Leerzeichen oder Anmeldedaten eingeben; oder leer lassen.",
                "Вебсайт: введіть коректну HTTP-/HTTPS-адресу без пробілів чи облікових даних; або залиште порожнім.",
            )
        OrganizationFormIssue.ADDRESS ->
            formText(language, "Adresse: höchstens 500 Zeichen.", "Адреса: не більше 500 символів.")
        OrganizationFormIssue.GERMAN_NAME ->
            formText(
                language,
                "Deutscher Name: höchstens 180 Zeichen.",
                "Назва німецькою: не більше 180 символів.",
            )
        OrganizationFormIssue.GERMAN_SUMMARY ->
            formText(
                language,
                "Deutsche Kurzbeschreibung: höchstens 160 Zeichen.",
                "Короткий опис німецькою: не більше 160 символів.",
            )
        OrganizationFormIssue.GERMAN_DETAILS ->
            formText(
                language,
                "Deutsche Beschreibung: höchstens 1200 Zeichen.",
                "Повний опис німецькою: не більше 1200 символів.",
            )
        OrganizationFormIssue.FORM ->
            formText(
                language,
                "Dieses Formular ist nicht gültig. Bitte schließen und erneut öffnen; es wurde nichts gesendet.",
                "Ця форма некоректна. Закрийте її та відкрийте знову; нічого не надіслано.",
            )
    }

private fun formText(language: String, german: String, ukrainian: String): String =
    if (language == "de") german else ukrainian
