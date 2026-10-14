import SwiftUI
import UIKit

extension Binding<String> {
    /// For text fields that wrap onto several lines: return is Done, so it closes the keyboard instead of adding
    /// a line break (a wrapping TextField otherwise always inserts one). Pair with `.submitLabel(.done)`.
    var doneOnReturn: Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                guard newValue.contains("\n") else {
                    wrappedValue = newValue
                    return
                }
                wrappedValue = newValue.replacingOccurrences(of: "\n", with: "")
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
    }
}
