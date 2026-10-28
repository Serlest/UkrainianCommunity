import SwiftUI
import UIKit

/// Nested previews share ownership; closing one cannot undo another view's wake request.
@MainActor final class SeasonalScreenAwakeLease {
    static let shared=SeasonalScreenAwakeLease()
    private var leases=Set<UUID>()
    private var original:Bool?
    var count:Int { leases.count }
    func acquire(_ id:UUID) {
        guard leases.insert(id).inserted else { return }
        if leases.count==1 { original=UIApplication.shared.isIdleTimerDisabled }
        UIApplication.shared.isIdleTimerDisabled=true
    }
    func release(_ id:UUID) {
        guard leases.remove(id) != nil else { return }
        if leases.isEmpty,let original { UIApplication.shared.isIdleTimerDisabled=original;self.original=nil }
    }
}

/// Owner-only local previews keep the device awake without changing any system lock setting.
struct SeasonalKeepAwake:ViewModifier {
    let enabled:Bool
    @State private var leaseID=UUID()
    private func update() {
        if enabled { SeasonalScreenAwakeLease.shared.acquire(leaseID) }
        else { SeasonalScreenAwakeLease.shared.release(leaseID) }
    }
    func body(content:Content) -> some View {
        content.onAppear(perform:update).onChange(of:enabled) { _,_ in update() }
            .onDisappear { SeasonalScreenAwakeLease.shared.release(leaseID) }
    }
}
