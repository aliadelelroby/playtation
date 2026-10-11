import AppKit
import Combine
import SwiftUI

struct Clock: View {
    var light: Bool
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(now, format: .dateTime.hour().minute())
            .font(PS.font(16, .bold))
            .foregroundStyle(light ? Color.white : Color.black)
            .frame(width: 88, alignment: .trailing)
            .onReceive(timer) { now = $0 }
    }
}
