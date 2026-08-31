/// The shared corner-radius scale. Numeric steps are named by size rather than
/// by a specific surface; `pill` is the semantic fully-rounded token.
public protocol CornerRadiusSystemProtocol {
    /// 4 — progress tracks, skeleton bars, and hairline chips.
    var xs: CornerRadius { get }
    /// 8 — small inline tags.
    var sm: CornerRadius { get }
    /// 12 — list rows and compact containers.
    var md: CornerRadius { get }
    /// 16 — input fields and inner icon tiles.
    var lg: CornerRadius { get }
    /// 24 — cards, banners, and list containers.
    var xl: CornerRadius { get }
    /// Fully rounded at every surface size the app can render.
    var pill: CornerRadius { get }
}
