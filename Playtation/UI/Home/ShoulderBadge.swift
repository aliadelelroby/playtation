import Combine
import SwiftUI

struct ShoulderBadge: View {
    var label: String

    var body: some View {
        Text(label)
            .font(PS.font(11, .bold))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .glassCapsule(clear: true)
    }
}
