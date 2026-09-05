package at.uac.android.feature.personal

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionCard
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.tr

/** The same welcome/public-browsing hierarchy as build 65, without initializing an auth form. */
@Composable
fun GuestProfileContent(
    language: String,
    onLogin: () -> Unit,
    onRegister: () -> Unit,
    onNavigate: (String) -> Unit,
) {
    UacSectionCard(
        tr(language, "Willkommen", "Ласкаво просимо"),
        tr(
            language,
            "Erstellen Sie einen Account, um Veranstaltungen zu speichern, Organisationen zu folgen und Benachrichtigungen zu erhalten.",
            "Створіть акаунт, щоб зберігати події, підписуватись на організації та отримувати сповіщення.",
        ),
        Modifier.testTag("guest-welcome"),
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onLogin,
                Modifier.heightIn(min = UacDesign.minimumTouch).testTag("guest-sign-in"),
            ) {
                Text(tr(language, "Anmelden", "Увійти"))
            }
            FilledTonalButton(
                onRegister,
                Modifier.fillMaxWidth()
                    .heightIn(min = UacDesign.minimumTouch)
                    .testTag("guest-create-account"),
                colors =
                    ButtonDefaults.filledTonalButtonColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ),
            ) {
                Text(tr(language, "Konto erstellen", "Створити акаунт"))
            }
        }
    }
    UacSectionCard(
        tr(language, "Ohne Account verfügbar", "Доступно без акаунта"),
        tr(
            language,
            "Die wichtigsten Inhalte können Sie sofort ansehen.",
            "Основний контент можна переглядати одразу.",
        ),
    ) {
        ProfileNavigationRow(
            tr(language, "News ansehen", "Перегляд новин"),
            tr(
                language,
                "Community-Updates und wichtige Mitteilungen.",
                "Оновлення громади та важливі повідомлення.",
            ),
            UacIcon.NEWS,
            "guest-browse-news",
        ) {
            onNavigate("home")
        }
        ProfileNavigationRow(
            tr(language, "Veranstaltungen ansehen", "Перегляд подій"),
            tr(
                language,
                "Treffen, Beratungen und Veranstaltungen in Ihrer Nähe.",
                "Зустрічі, консультації та події поруч.",
            ),
            UacIcon.CALENDAR,
            "guest-browse-events",
        ) {
            onNavigate("events")
        }
        ProfileNavigationRow(
            tr(language, "Organisationen ansehen", "Перегляд організацій"),
            tr(
                language,
                "Geprüfte Organisationen und Initiativen.",
                "Перевірені організації та ініціативи.",
            ),
            UacIcon.ORGANIZATIONS,
            "guest-browse-organizations",
        ) {
            onNavigate("organizations")
        }
    }
    UacSectionCard(
        tr(language, "Einstellungen und Support", "Налаштування і підтримка"),
        tr(
            language,
            "Grundlegende App-Einstellungen und rechtliche Informationen.",
            "Базові параметри застосунку та юридична інформація.",
        ),
    ) {
        ProfileNavigationRow(
            tr(language, "Einstellungen und Datenschutz", "Налаштування та приватність"),
            tr(
                language,
                "Sprache, Darstellung und rechtliche Hinweise.",
                "Мова, вигляд та юридична інформація.",
            ),
            UacIcon.SETTINGS,
            "guest-settings",
        ) {
            onNavigate("settings")
        }
    }
}

@Composable
fun ProfileNavigationRow(
    title: String,
    subtitle: String?,
    icon: UacIcon,
    tag: String,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = 58.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(tag)
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            Modifier.size(32.dp),
            shape = RoundedCornerShape(9.dp),
            color = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ) {
            Box(contentAlignment = Alignment.Center) { UacSymbol(icon) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            subtitle?.takeIf(String::isNotBlank)?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        UacSymbol(UacIcon.BACK, modifier = Modifier.rotate(180f))
    }
}
