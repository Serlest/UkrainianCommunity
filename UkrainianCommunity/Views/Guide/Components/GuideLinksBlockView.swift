import SwiftUI

struct GuideLinksBlockView: View {
    let block: GuideContentBlock.LinksBlock

    var body: some View {
        if !renderableLinks.isEmpty {
            DetailCard {
                GuideBlockTitleView(title: block.title)

                ForEach(renderableLinks) { link in
                    GuideSourceLinkRow(link: link)
                }
            }
        }
    }

    private var renderableLinks: [GuideSourceLink] {
        block.links.filter(\.isRenderable)
    }
}
