package at.uac.android.feature.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/** Local reference reader is available to guests; opening a document does not accept it. */
@Composable
fun ReferenceLegalLinks(language: String) {
    val context = LocalContext.current
    val documents = remember(context) { bundledReferenceLegal(context).take(2) }
    var opened by remember { mutableStateOf<AuthLegalDocument?>(null) }
    Text(
        authText(
            language,
            "Rechtliche Referenz für diese lokale Testversion",
            "Юридичні довідкові документи локальної тестової версії",
        ),
        style = MaterialTheme.typography.bodySmall,
    )
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        documents.forEach { document ->
            TextButton({ opened = document }, Modifier.testTag("settings-legal-${document.type}")) {
                Text(document.title(language))
            }
        }
    }
    opened?.let { AuthLegalReader(it, language, reference = true) { opened = null } }
}
