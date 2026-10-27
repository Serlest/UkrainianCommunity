import SwiftUI

struct ProjectSupportURLTesting: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestProjectSupportOpenFailure"] == "1" {
            content.environment(\.openURL, OpenURLAction { _ in .discarded })
        } else { content }
        #else
        content
        #endif
    }
}
