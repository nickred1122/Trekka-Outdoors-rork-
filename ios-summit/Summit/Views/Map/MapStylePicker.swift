import SwiftUI

/// The base-map chooser that sits on top of a map.
///
/// It replaces the button that cycled through the styles one tap at a time. With
/// three styles a cycle was tolerable; with five it means tapping blind and
/// hoping, so the styles are simply listed. Each one says what it is and whether
/// it survives losing signal, because that is the question that actually matters
/// on a mountainside.
struct MapStylePicker: View {
    @Binding var selection: TopoBaseStyle
    /// The styles on offer. The planner passes a shorter list, because editing
    /// runs on Apple's map and cannot draw Trekka's own sheet.
    var styles: [TopoBaseStyle] = TopoBaseStyle.allCases
    var onChange: () -> Void = {}

    var body: some View {
        Menu {
            Picker("Base map", selection: pickerBinding) {
                ForEach(styles) { style in
                    Label {
                        Text(style.title)
                    } icon: {
                        Image(systemName: style.symbol)
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.inline)

            Section {
                Text(selection.detail)
            }
        } label: {
            Image(systemName: selection.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.mapControlLabel)
                .frame(width: 44, height: 44)
                .background(Theme.mapControl, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.mapControlBorder, lineWidth: 1)
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel("Base map: \(selection.title)")
    }

    /// Menu pickers write straight through, so the haptic has to be hung off the
    /// write rather than an `onChange` that would also fire on a programmatic set.
    private var pickerBinding: Binding<TopoBaseStyle> {
        Binding(
            get: { selection },
            set: { newValue in
                guard newValue != selection else { return }
                selection = newValue
                onChange()
            }
        )
    }
}
