import SwiftUI
import UIKit

struct DismissKeyboardOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}

extension View {
    func dismissesKeyboardOnBackgroundTap() -> some View {
        modifier(DismissKeyboardOnTapModifier())
    }
}
