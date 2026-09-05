package at.uac.android

import at.uac.android.feature.auth.AuthValidation
import at.uac.android.feature.organization.*
import org.junit.Assert.*
import org.junit.Test

class OrganizationFormTest {
    private val valid =
        OrganizationDraft(
            id = "synthetic-form",
            name = "Synthetic Organization",
            summary = "A complete synthetic description",
            city = "Wien",
            region = "wien",
        )

    private fun assertProjection(draft: OrganizationDraft, field: OrganizationFormField? = null) {
        val issues = organizationFormIssues(draft)
        assertEquals(
            "Projection must agree with unchanged contract",
            runCatching { OrganizationContract.validate(draft) }.isFailure,
            issues.isNotEmpty(),
        )
        field?.let { assertTrue("Missing issue for $it", it in issues) }
    }

    @Test
    fun validDraftAndNormalizedWhitespaceHaveNoErrors() {
        assertProjection(valid)
        assertTrue(organizationFormIssues(valid).isEmpty())
        assertProjection(
            valid.copy(
                name = " ${valid.name} ",
                summary = " ${valid.summary} ",
                city = " Wien ",
                email = " user@example.invalid ",
                website = " example.invalid ",
            )
        )
        assertTrue(
            organizationFormIssues(
                    valid.copy(email = " a@b ", website = "example.invalid:8443/path")
                )
                .isEmpty()
        )
    }

    @Test
    fun nameCityAndOptionalContactBoundariesMatchContract() {
        listOf(0, 1, 179, 180, 181).forEach { assertProjection(valid.copy(name = "x".repeat(it))) }
        listOf(0, 1, 159, 160, 161).forEach { assertProjection(valid.copy(city = "x".repeat(it))) }
        listOf(0, 79, 80, 81).forEach { assertProjection(valid.copy(phone = "1".repeat(it))) }
        listOf(0, 499, 500, 501).forEach { assertProjection(valid.copy(address = "x".repeat(it))) }
        assertProjection(valid.copy(name = " "), OrganizationFormField.NAME)
        assertProjection(valid.copy(city = " "), OrganizationFormField.CITY)
    }

    @Test
    fun summaryAndDetailsUseCodePointsNotUtf16Length() {
        listOf(0, 19, 20, 159, 160, 161).forEach {
            assertProjection(valid.copy(summary = "x".repeat(it)))
            assertProjection(valid.copy(summary = "😀".repeat(it)))
        }
        listOf(0, 1199, 1200, 1201).forEach {
            assertProjection(valid.copy(details = "😀".repeat(it)))
        }
        assertTrue(organizationFormIssues(valid.copy(summary = "😀".repeat(160))).isEmpty())
        assertProjection(valid.copy(summary = "😀".repeat(161)), OrganizationFormField.SUMMARY)
        assertProjection(valid.copy(details = "😀".repeat(1201)), OrganizationFormField.DETAILS)
    }

    @Test
    fun nameRetainsExistingUtf16LimitWithoutTighteningIt() {
        assertTrue(organizationFormIssues(valid.copy(name = "😀".repeat(90))).isEmpty())
        assertProjection(valid.copy(name = "😀".repeat(91)), OrganizationFormField.NAME)
    }

    @Test
    fun emailUsesExistingRulesNotAnInventedStricterRegex() {
        listOf(
                "",
                "a@b",
                "@",
                "bad-email",
                "a @b",
                "a@\tb",
                "x".repeat(319) + "@",
                "x".repeat(320) + "@",
            )
            .forEach {
                assertProjection(valid.copy(email = it))
            }
        assertTrue(organizationFormIssues(valid.copy(email = "@")).isEmpty())
        assertProjection(valid.copy(email = "bad-email"), OrganizationFormField.EMAIL)
        assertTrue(organizationFormIssues(valid.copy(email = "user@example.invalid")).isEmpty())
    }

    @Test
    fun websiteReusesExactCanonicalValidator() {
        listOf(
                "",
                "example.invalid",
                "http://example.invalid",
                "https://example.invalid",
                "example.invalid:8443/a",
                "file:///tmp/photo",
                "ftp://example.invalid",
                "https://user:pass@example.invalid",
                "https://bad host.invalid",
                "https://example.invalid:65536",
                "https://example.invalid/" + "x".repeat(2050),
            )
            .forEach {
                assertProjection(valid.copy(website = it))
            }
        assertProjection(valid.copy(website = "file:///tmp/photo"), OrganizationFormField.WEBSITE)
    }

    @Test
    fun germanTranslationBoundariesStayOptionalAndExact() {
        listOf(0, 180, 181).forEach { assertProjection(valid.copy(germanName = "x".repeat(it))) }
        listOf(0, 160, 161).forEach {
            assertProjection(valid.copy(germanSummary = "😀".repeat(it)))
        }
        listOf(0, 1200, 1201).forEach {
            assertProjection(valid.copy(germanDetails = "😀".repeat(it)))
        }
        assertProjection(
            valid.copy(germanName = "x".repeat(181)),
            OrganizationFormField.GERMAN_NAME,
        )
        assertProjection(
            valid.copy(germanSummary = "x".repeat(161)),
            OrganizationFormField.GERMAN_SUMMARY,
        )
        assertProjection(
            valid.copy(germanDetails = "x".repeat(1201)),
            OrganizationFormField.GERMAN_DETAILS,
        )
    }

    @Test
    fun choicesAreExactKeysAndUnknownIdentityIsNotSilentlyValid() {
        AuthValidation.regions.forEach { assertProjection(valid.copy(region = it)) }
        OrganizationContract.profileKinds.forEach { assertProjection(valid.copy(profileKind = it)) }
        listOf("", "Wien", " wien", "unknown").forEach {
            assertProjection(valid.copy(region = it), OrganizationFormField.REGION)
        }
        listOf("", "Community", "unknown").forEach {
            assertProjection(valid.copy(profileKind = it), OrganizationFormField.PROFILE_KIND)
        }
        listOf("", "bad/id", "ukrainian-community").forEach {
            assertProjection(valid.copy(id = it), OrganizationFormField.FORM)
        }
    }

    @Test
    fun correctionRemovesSpecificIssueWithoutHidingOtherFields() {
        val broken = valid.copy(email = "bad-email", website = "file:///tmp/photo")
        assertEquals(
            setOf(OrganizationFormField.EMAIL, OrganizationFormField.WEBSITE),
            organizationFormIssues(broken).keys,
        )
        assertEquals(
            setOf(OrganizationFormField.WEBSITE),
            organizationFormIssues(broken.copy(email = "a@b")).keys,
        )
        assertTrue(
            organizationFormIssues(broken.copy(email = "a@b", website = "example.invalid"))
                .isEmpty()
        )
    }

    @Test
    fun everyCanonicalChoiceHasGermanAndUkrainianLabel() {
        AuthValidation.regions.forEach { key ->
            val de = organizationRegionLabel(key, "de")
            val uk = organizationRegionLabel(key, "uk")
            assertTrue(de.isNotBlank() && uk.isNotBlank())
            assertNotEquals(key, de)
            assertNotEquals(de, uk)
        }
        OrganizationContract.profileKinds.forEach { key ->
            val de = organizationProfileKindLabel(key, "de")
            val uk = organizationProfileKindLabel(key, "uk")
            assertTrue(de.isNotBlank() && uk.isNotBlank())
            assertNotEquals(key, de)
            assertNotEquals(de, uk)
        }
        assertEquals("Niederösterreich", organizationRegionLabel("niederoesterreich", "de"))
        assertEquals("Нижня Австрія", organizationRegionLabel("niederoesterreich", "uk"))
        assertEquals("Медіапроєкт", organizationProfileKindLabel("mediaProject", "uk"))
    }

    @Test
    fun invalidChoiceShowsExplanationNotRawKeyOrValidFallback() {
        listOf("de", "uk").forEach { language ->
            assertNotEquals(
                "private-untrusted-key",
                organizationRegionLabel("private-untrusted-key", language),
            )
            assertNotEquals(
                organizationProfileKindLabel("community", language),
                organizationProfileKindLabel("unknown", language),
            )
            assertNotEquals(
                organizationRegionLabel("wien", language),
                organizationRegionLabel("", language),
            )
        }
    }

    @Test
    fun everyIssueHasSpecificLocalizedExplanation() {
        OrganizationFormIssue.entries.forEach { issue ->
            val de = organizationFormIssueText(issue, "de")
            val uk = organizationFormIssueText(issue, "uk")
            assertTrue(de.isNotBlank() && uk.isNotBlank())
            assertNotEquals(de, uk)
        }
    }
}
