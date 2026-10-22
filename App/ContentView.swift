import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 40))
            Text("Keyline")
                .font(.title)
            Text("No servers yet.")
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 320)
    }
}
