import Combine
import SwiftUI

struct DashClock: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(label)
            .font(PS.font(22, .regular))
            .foregroundStyle(.white)
            .frame(minWidth: 108, alignment: .trailing)
            .onReceive(timer) { now = $0 }
    }

    private var label: String {
        let hour = Calendar.current.component(.hour, from: now)
        let minute = Calendar.current.component(.minute, from: now)
        let suffix = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h, minute, suffix)
    }
}
