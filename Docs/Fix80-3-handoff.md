# Fix80-3 handoff

## Coordinator-owned localization dependency

The managed-organization deletion dialog now uses the localization key \`organizations.delete.cascade_message\` directly with a Ukrainian fallback so this package remains buildable without editing coordinator-owned localization files.

Please add the key to \`UkrainianCommunity/Localization/Localizable.xcstrings\` and expose it as \`AppStrings.Organizations.deleteCascadeMessage\` in \`UkrainianCommunity/Utilities/AppStrings.swift\`, then replace the private fallback in \`ManagedOrganizationView\` with that API.

Suggested copy:

- Ukrainian: \`Організацію, її новини, події, фото, вподобання, підписки та закладки буде видалено назавжди. Якщо є активні події, спочатку завершіть або скасуйте їх.\`
- German: \`Die Organisation sowie ihre Nachrichten, Veranstaltungen, Fotos, Likes, Follows und Lesezeichen werden dauerhaft gelöscht. Wenn aktive Veranstaltungen vorhanden sind, müssen sie zuerst beendet oder abgesagt werden.\`
- English: \`The organization and its news, events, photos, likes, follows, and bookmarks will be permanently deleted. If there are active events, finish or cancel them first.\`
