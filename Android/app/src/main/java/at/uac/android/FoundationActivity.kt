package at.uac.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.content.edit
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.foundation.*
import java.util.Locale

/** Non-exported diagnostic screen. Package-1 regression remains executable. */
class FoundationActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val preferences = applicationContext.getSharedPreferences("uac-local", MODE_PRIVATE)
        val factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    FoundationViewModel(
                        SyntheticFoundationRepository(),
                        EmulatorFoundationRepository(LocalFirebase.firestore(applicationContext)),
                        preferences.getString("language", null)
                            ?: if (Locale.getDefault().language == "uk") "uk" else "de",
                        { selected -> preferences.edit { putString("language", selected) } },
                    )
                        as T
            }
        setContent {
            val model: FoundationViewModel = viewModel(factory = factory)
            FoundationScreen(
                model.state.collectAsStateWithLifecycle().value,
                model::selectLanguage,
                model::selectMode,
                model::reload,
            )
        }
    }
}
