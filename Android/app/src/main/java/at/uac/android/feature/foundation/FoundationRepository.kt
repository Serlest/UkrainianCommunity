package at.uac.android.feature.foundation

data class LocalizedText(val de: String, val uk: String) {
    fun resolve(language: String): String = if (language == "uk") uk else de
}

data class FoundationContent(val title: LocalizedText, val body: LocalizedText)

interface FoundationRepository {
    suspend fun load(): FoundationContent
}

class SyntheticFoundationRepository : FoundationRepository {
    override suspend fun load() =
        FoundationContent(
            LocalizedText("Gemeinsam in Österreich", "Разом в Австрії"),
            LocalizedText(
                "Nachrichten, Veranstaltungen und Organisationen — hier entsteht UAC für Android.",
                "Новини, події та організації — тут створюється UAC для Android.",
            ),
        )
}

class InvalidFixtureException : Exception()

class FixtureAccessDeniedException : Exception()

/** A deliberately small probe contract, NOT the complete production News model. */
fun decodeFoundationFixture(data: Map<String, Any?>): FoundationContent {
    if (data["moderationStatus"] != "approved") throw InvalidFixtureException()
    val localizations = data["localizations"] as? Map<*, *> ?: throw InvalidFixtureException()
    fun text(language: String, field: String): String =
        ((localizations[language] as? Map<*, *>)?.get(field) as? String)?.takeIf { it.isNotBlank() }
            ?: throw InvalidFixtureException()
    return FoundationContent(
        LocalizedText(text("de", "title"), text("uk", "title")),
        LocalizedText(text("de", "body"), text("uk", "body")),
    )
}
