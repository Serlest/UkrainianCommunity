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
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Build-65 feed structure: media + compact type/title/metadata, stacked for accessibility sizes.
 */
@Composable
fun ContentCard(item: Content, language: String, onClick: () -> Unit) {
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
                item.fields.string("logoURL").ifEmpty { item.fields.string("imageURL") }
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
        Modifier.widthIn(max = UacDesign.readableWidth)
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
                media()
                Box(Modifier.weight(1f)) {
                    FeedCardDetails(item, language, icon, accent, fill, false)
                }
                if (item.kind == ContentKind.EVENTS) EventDateBadge(item, language)
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
        Surface(color = fill, contentColor = accent, shape = RoundedCornerShape(8.dp)) {
            Row(
                Modifier.padding(horizontal = 7.dp, vertical = 3.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                UacSymbol(icon, modifier = Modifier.size(13.dp))
                Text(item.kind.label(language), style = MaterialTheme.typography.labelSmall)
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
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = if (largeText) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        val publisher =
            item.fields.string("organizationName").ifEmpty {
                item.fields.string("authorDisplayName")
            }
        if (publisher.isNotBlank() && item.kind != ContentKind.ORGANIZATIONS)
            Text(
                publisher,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = maximum,
                overflow = TextOverflow.Ellipsis,
            )
        val date =
            if (item.kind == ContentKind.EVENTS) item.fields.time("startDate") else item.publishedAt
        val metadata =
            listOfNotNull(
                    item.fields.string("city").takeIf(String::isNotBlank),
                    date?.let {
                        if (item.kind == ContentKind.EVENTS)
                            DateTimeFormatter.ofPattern("HH:mm", Locale.forLanguageTag(language))
                                .withZone(ZoneId.systemDefault())
                                .format(it)
                        else
                            DateTimeFormatter.ofPattern(
                                    "dd.MM.yyyy",
                                    Locale.forLanguageTag(language),
                                )
                                .withZone(ZoneId.systemDefault())
                                .format(it)
                    },
                )
                .joinToString(" · ")
        if (metadata.isNotBlank())
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
private fun EventDateBadge(item: Content, language: String) {
    val date = item.fields.time("startDate")?.atZone(ZoneId.systemDefault()) ?: return
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
        }
    }
}
