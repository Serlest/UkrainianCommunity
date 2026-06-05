import SwiftUI

struct LegalMarkdownRenderer: View {
    let markdown: String
    let fallbackText: String?

    init(markdown: String, fallbackText: String? = nil) {
        self.markdown = markdown
        self.fallbackText = fallbackText
    }

    private var blocks: [LegalMarkdownBlock] {
        LegalMarkdownParser.blocks(from: markdown, fallbackText: fallbackText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                blockView(block)
                    .padding(.top, topPadding(for: block, at: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: LegalMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            inlineText(block.text)
                .font(font(forHeadingLevel: level))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            inlineText(block.text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .top, spacing: 10) {
                Text("•")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                inlineText(block.text)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inlineText(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value) {
            return Text(attributed)
        }

        return Text(value)
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1:
            return .title3.weight(.bold)
        case 2:
            return .headline.weight(.semibold)
        default:
            return .subheadline.weight(.semibold)
        }
    }

    private func topPadding(for block: LegalMarkdownBlock, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }

        switch block.kind {
        case .heading(let level):
            return level == 1 ? 22 : 18
        case .paragraph:
            return 12
        case .bullet:
            return 8
        }
    }
}

private struct LegalMarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind
    let text: String

    enum Kind {
        case heading(level: Int)
        case paragraph
        case bullet
    }
}

private enum LegalMarkdownParser {
    static func blocks(from markdown: String, fallbackText: String?) -> [LegalMarkdownBlock] {
        let source = normalizedSource(markdown: markdown, fallbackText: fallbackText)
        var blocks: [LegalMarkdownBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let text = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                blocks.append(LegalMarkdownBlock(kind: .paragraph, text: text))
            }

            paragraphLines.removeAll()
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = heading(from: line) {
                flushParagraph()
                blocks.append(LegalMarkdownBlock(kind: .heading(level: heading.level), text: heading.text))
                continue
            }

            if let bulletText = bulletText(from: line) {
                flushParagraph()
                blocks.append(LegalMarkdownBlock(kind: .bullet, text: bulletText))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks
    }

    private static func normalizedSource(markdown: String, fallbackText: String?) -> String {
        let normalizedMarkdown = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedMarkdown.isEmpty {
            return normalizedMarkdown
        }

        return fallbackText?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        for level in 1...3 {
            let marker = String(repeating: "#", count: level) + " "
            guard line.hasPrefix(marker) else { continue }

            let text = String(line.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (level, text)
        }

        return nil
    }

    private static func bulletText(from line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else {
            return nil
        }

        let text = String(line.dropFirst(2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
