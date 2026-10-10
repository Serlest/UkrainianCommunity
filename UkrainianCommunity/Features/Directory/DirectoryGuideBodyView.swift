import SwiftUI

struct DirectoryGuideBodyView: View {
    let text: String
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let blocks = DirectoryReadingBlocks.from(text)
            if compact, let first = blocks.first {
                Text(first)
                    .font(.body.weight(.medium))
                    .lineSpacing(5)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if blocks.count > 1 {
                    Text(blocks.dropFirst().joined(separator: " "))
                        .font(.body)
                        .lineSpacing(5)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    Text(block)
                        .font(.body.weight(index == 0 && block.count <= 140 ? .medium : .regular))
                        .lineSpacing(5)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

enum DirectoryReadingBlocks {
    static func from(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap { line in
                // Protect dates and list numbers from sentence splitting.
                let protected = line.replacingOccurrences(
                    of: #"(?<!\d)(\d{1,2})\.(?=\d|\s+\p{L})"#,
                    with: "$1\u{E000}", options: .regularExpression
                )
                let value = protected as NSString
                var blocks: [String] = []
                value.enumerateSubstrings(
                    in: NSRange(location: 0, length: value.length), options: .bySentences
                ) { substring, _, _, _ in
                    guard let sentence = substring?
                        .replacingOccurrences(of: "\u{E000}", with: ".")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !sentence.isEmpty else { return }
                    if sentence.count < 18, !blocks.isEmpty,
                       sentence.range(of: #"^\d+\."#, options: .regularExpression) == nil {
                        blocks[blocks.count - 1] += " " + sentence
                    } else {
                        blocks.append(sentence)
                    }
                }
                return blocks.isEmpty ? [line] : blocks
            }
    }
}
