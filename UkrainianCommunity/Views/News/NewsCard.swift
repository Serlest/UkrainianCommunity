import SwiftUI
import UIKit

struct NewsCard: View {
    let post: NewsPost
    var previewImage: UIImage? = nil

    var body: some View {
        ContentFeedCard(item: HomeFeedItem(post: post), previewImage: previewImage)
    }
}
