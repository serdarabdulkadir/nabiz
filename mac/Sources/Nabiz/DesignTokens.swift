// Gorsel dil: koseler, renkler, hareket ve ortak hap secici. Ayrinti: docs/tasarim.md "Gorsel dil".
import SwiftUI

/// Eşmerkezli köşe ölçeği: dış yarıçap = iç yarıçap + padding. Hepsi `.continuous`.
enum Radius {
    static let tile: CGFloat = 22     // panel karolari (panel padding 12)
    static let group: CGFloat = 18    // panelde satir gruplari
    static let card: CGFloat = 16     // ayarlarda Box / kart kaplari
    static let row: CGFloat = 10      // kart ici ogeler
}

enum Palette {
    static let fill = Color.primary.opacity(0.06)       // kutu / kart dolgusu
    static let fillSubtle = Color.primary.opacity(0.05)
    static let track = Color.primary.opacity(0.12)      // halka / cubuk izi
    static let selection = Color.primary.opacity(0.14)  // secili hap
    static let stroke = Color.primary.opacity(0.1)
    static let warning = Color.orange
    static let critical = Color.red
    static let charging = Color.green

    /// Halka/deger rengi: kritik kirmizi, uyari turuncu, normalde primary.
    static func tint(critical: Bool, warning: Bool) -> Color {
        critical ? Self.critical : (warning ? Self.warning : Color.primary)
    }
}

enum Thresholds {
    /// CPU / bellek / disk uyari esigi (kritik esikler ayri, mevcut mantikta kalir).
    static let warning = 0.75
}

enum Motion {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    static let ring = Animation.smooth(duration: 0.5)
}

extension View {
    func roundedDigits(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        self.font(.system(size: size, weight: weight, design: .rounded)).monospacedDigit()
    }

    func fillBox(radius: CGFloat) -> some View {
        self.background(Palette.fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: Yonlu gecis

/// Yeni icerik hareket yonunden gelir (kayma + opaklik + hafif blur), eskisi ters yone gider.
struct DirectionalShift: ViewModifier {
    var offset: CGFloat
    var active: Bool
    func body(content: Content) -> some View {
        content
            .offset(x: active ? offset : 0)
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 4 : 0)
    }
}

extension AnyTransition {
    /// forward = true: yeni icerik sagdan gelir, eskisi sola gider.
    static func directional(forward: Bool, distance: CGFloat = 16) -> AnyTransition {
        let s: CGFloat = forward ? 1 : -1
        return .asymmetric(
            insertion: .modifier(active: DirectionalShift(offset: distance * s, active: true),
                                 identity: DirectionalShift(offset: 0, active: false)),
            removal: .modifier(active: DirectionalShift(offset: -distance * s, active: true),
                               identity: DirectionalShift(offset: 0, active: false)))
    }
}

// MARK: Hap secici

/// Tek kapsul secili arka plan secenekler arasinda kayar (matchedGeometryEffect).
struct SlidingPillPicker<T: Hashable>: View {
    let options: [T]
    let selection: T
    let title: (T) -> String
    var fontSize: CGFloat? = nil
    var horizontalPadding: CGFloat = 0
    var verticalPadding: CGFloat = 6
    var fill = true
    let onSelect: (T) -> Void

    @Namespace private var ns

    var body: some View {
        GlassGroup {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { o in
                    let on = o == selection
                    Button { onSelect(o) } label: {
                        Text(title(o))
                            .font(fontSize.map { .system(size: $0, weight: on ? .semibold : .regular) }
                                  ?? .callout.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.primary : Color.secondary)
                            .frame(maxWidth: fill ? .infinity : nil)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, verticalPadding)
                            .background {
                                if on {
                                    Capsule(style: .continuous).fill(Palette.selection)
                                        .matchedGeometryEffect(id: "pill", in: ns)
                                }
                            }
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(PillPressStyle())
                }
            }
            .padding(3)
            .glassCapsule()
            .animation(Motion.spring, value: selection)
            .sensoryFeedback(.selection, trigger: selection)
        }
    }
}

struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
