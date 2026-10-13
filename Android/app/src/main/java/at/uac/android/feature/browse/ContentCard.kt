package at.uac.android.feature.browse

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import at.uac.android.design.LocalUacDark
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSymbol
import java.time.ZoneId
import java.time.Instant
import java.time.Duration
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Build-65 feed structure: media + compact type/title/metadata, stacked for accessibility sizes.
 */
@Composable
fun ContentCard(item: Content, language: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val largeText = LocalDensity.current.fontScale > 1.3f
    val icon =
        when (item.kind) {
            ContentKind.NEWS -> UacIcon.NEWS
            ContentKind.EVENTS -> UacIcon.CALENDAR
            ContentKind.ORGANIZATIONS -> UacIcon.ORGANIZATIONS
        }
    val colors = MaterialTheme.colorScheme
    val dark = LocalUacDark.current
    val accent =
        when (item.kind) {
            ContentKind.NEWS -> if (dark) UacDesign.successDark else UacDesign.successLight
            ContentKind.ORGANIZATIONS -> colors.tertiary
            ContentKind.EVENTS -> colors.primary
        }
    val fill =
        when (item.kind) {
            ContentKind.NEWS -> if (dark) UacDesign.successFillDark else UacDesign.successFillLight
            ContentKind.ORGANIZATIONS -> colors.tertiaryContainer
            ContentKind.EVENTS -> colors.primaryContainer
        }
    val media: @Composable () -> Unit = {
        val url =
            if (item.kind == ContentKind.ORGANIZATIONS)
                organizationImageUrl(item.fields, preferCover = false)
            else item.fields.string("imageURL")
        CompositionLocalProvider(LocalContentColor provides accent) {
            PublicImage(
                url,
                "",
                language,
                Modifier.size(72.dp).clip(RoundedCornerShape(13.dp)).background(fill),
                compact = true,
                fallback = icon,
            )
        }
    }
    Card(
        onClick,
        modifier.widthIn(max = UacDesign.readableWidth)
            .fillMaxWidth()
            .testTag("card-${item.id}")
            .semantics(mergeDescendants = true) {},
        shape = RoundedCornerShape(UacDesign.cardRadius),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
    ) {
        if (largeText)
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    media()
                    if (item.kind == ContentKind.EVENTS) EventDateBadge(item, language)
                }
                    FeedCardDetails(item, language, icon, accent, fill, true)
            }
        else
            Row(
                Modifier.padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (item.kind == ContentKind.EVENTS) EventDateBadge(item, language)
                else media()
                Box(Modifier.weight(1f)) {
                    FeedCardDetails(item, language, icon, accent, fill, false)
                }
                if (item.kind == ContentKind.EVENTS) media()
                if (item.kind == ContentKind.NEWS) NewsRelativeDate(item, language)
            }
    }
}

@Composable
private fun FeedCardDetails(
    item: Content,
    language: String,
    icon: UacIcon,
    accent: androidx.compose.ui.graphics.Color,
    fill: androidx.compose.ui.graphics.Color,
    largeText: Boolean,
) {
    val maximum = if (largeText) Int.MAX_VALUE else 2
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (item.kind != ContentKind.ORGANIZATIONS) {
            Surface(color = fill, contentColor = accent, shape = RoundedCornerShape(8.dp)) {
                Row(
                    Modifier.padding(horizontal = 7.dp, vertical = 3.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    UacSymbol(icon, modifier = Modifier.size(13.dp))
                    Text(
                        if (item.kind == ContentKind.NEWS)
                            tr(language, "NEUIGKEITEN", "НОВИНИ")
                        else tr(language, "TERMINE", "ПОДІЇ"),
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        }
        Text(
            item.title(language),
            Modifier.testTag("card-title-${item.id}"),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = maximum,
            overflow = TextOverflow.Ellipsis,
        )
        item.summary(language).takeIf(String::isNotBlank)?.let {
            Text(
                it,
                style = if (item.kind == ContentKind.NEWS && !largeText)
                    MaterialTheme.typography.labelMedium else MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = if (largeText) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        val publisher =
            item.fields.string("organizationName").ifEmpty {
                item.fields.string("authorDisplayName")
            }
        if (publisher.isNotBlank() && item.kind != ContentKind.ORGANIZATIONS &&
            (item.kind != ContentKind.EVENTS || largeText))
            Text(
                publisher,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = maximum,
                overflow = TextOverflow.Ellipsis,
            )
        val eventOccurrence = if (item.kind == ContentKind.EVENTS)
            item.fields.displayEventOccurrence(Instant.now()) else null
        val date = eventOccurrence?.start ?: item.publishedAt
        val metadataParts =
            listOfNotNull(
                    item.fields.string("city").takeIf(String::isNotBlank),
                    date?.let {
                        if (eventOccurrence != null) {
                            if (eventOccurrence.allDay) tr(language, "Ganztägig", "Увесь день")
                            else {
                                val clock = DateTimeFormatter.ofPattern("HH:mm", Locale.forLanguageTag(language))
                                    .withZone(ZoneId.systemDefault())
                                "${clock.format(eventOccurrence.start)}–${clock.format(eventOccurrence.end)}"
                            }
                        }
                        else
                            DateTimeFormatter.ofPattern(
                                    "dd.MM.yyyy",
                                    Locale.forLanguageTag(language),
                                )
                                .withZone(ZoneId.systemDefault())
                                .format(it)
                    },
                )
        val metadata = (if (item.kind == ContentKind.EVENTS) metadataParts.reversed()
            else metadataParts).joinToString(" · ")
        val organizationRegion = item.fields.string("federalState")
            .takeIf(String::isNotBlank)?.let { localizedRegionName(it, language) }
            ?: item.fields.string("city")
        if (item.kind == ContentKind.ORGANIZATIONS && !largeText && organizationRegion.isNotBlank())
            Surface(color = MaterialTheme.colorScheme.surfaceContainerLow,
                shape = RoundedCornerShape(12.dp)) {
                Text(organizationRegion, Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        else if (metadata.isNotBlank() && (item.kind != ContentKind.NEWS || largeText))
            Text(
                metadata,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = maximum,
                overflow = TextOverflow.Ellipsis,
            )
        if (item.fields.string("cancellationState") == "cancelled")
            Text(
                tr(language, "Abgesagt", "Скасовано"),
                Modifier.testTag("card-cancelled-${item.id}"),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.labelLarge,
            )
    }
}

@Composable
private fun NewsRelativeDate(item: Content, language: String) {
    val published = item.publishedAt ?: return
    val elapsed = Duration.between(published, Instant.now()).toMinutes().coerceAtLeast(0)
    val label = when {
        elapsed < 60 -> tr(language, "gerade eben", "щойно")
        elapsed < 1_440 -> {
            val hours = (elapsed / 60).coerceAtLeast(1)
            if (language == "uk") "$hours год тому"
            else if (hours == 1L) "vor 1 Std." else "vor $hours Std."
        }
        else -> {
            val days = elapsed / 1_440
            if (language == "uk") "$days дн. тому"
            else if (days == 1L) "vor 1 Tag" else "vor $days Tagen"
        }
    }
    Text(label, style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
}

@Composable
private fun EventDateBadge(item: Content, language: String) {
    val date = item.fields.displayEventOccurrence(Instant.now())?.start
        ?.atZone(ZoneId.systemDefault()) ?: return
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(
            Modifier.padding(horizontal = 9.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                date.dayOfMonth.toString(),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                DateTimeFormatter.ofPattern("MMM", Locale.forLanguageTag(language)).format(date),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
            Text(
                DateTimeFormatter.ofPattern("EEE", Locale.forLanguageTag(language)).format(date)
                    .uppercase(Locale.forLanguageTag(language)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
