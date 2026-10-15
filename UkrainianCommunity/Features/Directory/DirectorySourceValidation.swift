import Foundation

enum DirectorySourceValidation {
    static let nameLimit = 160
    static let urlLimit = 1024

    static func nameIssue(_ value: String) -> String? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DirectoryEditorText.value("Вкажіть назву установи або джерела.", "Geben Sie den Namen der Behörde oder Quelle an.")
        }
        if value.utf16.count > nameLimit {
            return DirectoryEditorText.value("Назва джерела: максимум \(nameLimit) символів.", "Quellenname: maximal \(nameLimit) Zeichen.")
        }
        return nil
    }

    static func urlIssue(_ value: String) -> String? {
        if value.isEmpty {
            return DirectoryEditorText.value("Додайте повну адресу сторінки, наприклад https://www.oesterreich.gv.at/.",
                                             "Geben Sie die vollständige Seitenadresse ein, z. B. https://www.oesterreich.gv.at/.")
        }
        if value.utf16.count > urlLimit {
            return DirectoryEditorText.value("Посилання: максимум \(urlLimit) символів.", "Link: maximal \(urlLimit) Zeichen.")
        }
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            return DirectoryEditorText.value("Потрібна повна HTTPS-адреса без пробілів, наприклад https://serlest.com/.",
                                             "Vollständige HTTPS-Adresse ohne Leerzeichen erforderlich, z. B. https://serlest.com/.")
        }
        return nil
    }
}
