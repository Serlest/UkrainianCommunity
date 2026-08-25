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
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: LegalMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            headingView(block.text, level: level)
        case .paragraph:
            inlineText(block.text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            listRow(marker: "•", text: block.text, numbered: false)
        case .ordered(let marker):
            listRow(marker: marker, text: block.text, numbered: true)
        }
    }

    @ViewBuilder
    private func headingView(_ value: String, level: Int) -> some View {
        if level == 2, let numbered = LegalMarkdownParser.numberedHeading(from: value) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(numbered.number)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.accentPrimarySoft, in: Capsule())

                inlineText(numbered.title)
                    .font(font(forHeadingLevel: level))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if level == 2 {
                    Capsule()
                        .fill(AppTheme.accentPrimary)
                        .frame(width: 34, height: 4)
                        .accessibilityHidden(true)
                }

                inlineText(value)
                    .font(font(forHeadingLevel: level))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func listRow(marker: String, text: String, numbered: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(marker)
                .font(numbered ? .caption.weight(.bold) : .body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 28, alignment: .center)
                .frame(minHeight: 24, alignment: .top)
                .background(numbered ? AppTheme.accentPrimarySoft : Color.clear, in: Capsule())
                .padding(.top, numbered ? 1 : 0)
                .accessibilityHidden(true)

            inlineText(text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func inlineText(_ value: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: value, options: options) {
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
        case .bullet, .ordered:
            return 10
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
        case ordered(marker: String)
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
                .joined(separator: "\n")
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

            if let orderedItem = orderedItem(from: line) {
                flushParagraph()
                blocks.append(
                    LegalMarkdownBlock(
                        kind: .ordered(marker: orderedItem.marker),
                        text: orderedItem.text
                    )
                )
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

    static func numberedHeading(from value: String) -> (number: String, title: String)? {
        guard let item = orderedItem(from: value) else { return nil }
        return (String(item.marker.dropLast()), item.text)
    }

    private static func orderedItem(from line: String) -> (marker: String, text: String)? {
        guard let separatorIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }) else {
            return nil
        }

        let number = line[..<separatorIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let afterSeparator = line.index(after: separatorIndex)
        guard afterSeparator < line.endIndex, line[afterSeparator].isWhitespace else { return nil }

        let text = line[afterSeparator...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return ("\(number).", text)
    }
}
