import SwiftUI

enum Palette {
    static let accent = Color("AccentColor")
    static let soft = Color("AccentSoft")
    static let surface = Color(.secondarySystemBackground)
}

extension Font {
    static func arabic(_ size: CGFloat) -> Font { .custom("Geeza Pro", size: size) }
}

/// Every place you can navigate to.
enum Route: Hashable {
    case lecture(String, Double)
    case series(String)
    case category(String)
    case year(Int)
    case theme(String)
    case themes
    case who
    case halaqah
    case halaqahLessons
    case halaqahLesson(Int)
    case halaqahExercises
    case halaqahExercise(String)
    case years
}

struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { r in
            switch r {
            case .lecture(let id, let t): LectureView(id: id, startAt: t)
            case .series(let s): SeriesView(slug: s)
            case .category(let c): CategoryView(categoryId: c)
            case .year(let y): YearView(year: y)
            case .years: YearsView()
            case .theme(let s): TopicView(slug: s)
            case .themes: ThemesView()
            case .who: WhoView()
            case .halaqah: HalaqahHomeView()
            case .halaqahLessons: HalaqahLessonsView()
            case .halaqahLesson(let n): HalaqahLessonView(n: n)
            case .halaqahExercises: HalaqahExercisesView()
            case .halaqahExercise(let id): HalaqahExerciseView(exerciseId: id)
            }
        }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }
}

struct LectureRow: View {
    let lecture: Lecture
    var showSeries = true
    var progress: StudyProgress? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lecture.title)
                .font(Fmt.isArabic(lecture.title) ? .arabic(18) : .body.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: Fmt.isArabic(lecture.title) ? .trailing : .leading)
            HStack(spacing: 8) {
                if showSeries, let s = lecture.s, !lecture.title.lowercased().hasPrefix(s.lowercased()) {
                    Text(s).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let p = progress {
                    Text("\(Fmt.time(Double(p.t)))\(p.d > 0 ? " / \(Fmt.time(Double(p.d)))" : "")").monospacedDigit()
                } else {
                    Text(lecture.durationText)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let p = progress, p.d > 0 {
                ProgressView(value: p.percent).tint(Palette.accent)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A tappable time stamp.
struct TimeChip: View {
    let t: Double
    var end: Double? = nil
    var body: some View {
        Text(end.map { "\(Fmt.time(t)) – \(Fmt.time($0))" } ?? Fmt.time(t))
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.soft, in: Capsule())
            .foregroundStyle(Palette.accent)
    }
}

struct VerseBlock: View {
    let label: String
    let arabic: String
    let english: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
            }
            if !arabic.isEmpty {
                Text(arabic)
                    .font(.arabic(21))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            if !english.isEmpty {
                Text(english).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct SurahHeader: View {
    let ranges: [VerseRange]

    struct SurahGroup {
        let surah: Int
        let ranges: [VerseRange]
        var arabicRanges: String {
            ranges.map { r in
                r.from == r.to ? Fmt.arabicNumber(r.from) : Fmt.arabicNumber(r.from) + "–" + Fmt.arabicNumber(r.to)
            }.joined(separator: "، ")
        }
        var latinRanges: String {
            Quran.name(surah) + " " + ranges.map { r in
                r.from == r.to ? "\(surah):\(r.from)" : "\(surah):\(r.from)–\(r.to)"
            }.joined(separator: ", ")
        }
    }

    var groups: [SurahGroup] {
        var order: [Int] = []
        var by: [Int: [VerseRange]] = [:]
        for r in ranges {
            if by[r.surah] == nil { order.append(r.surah) }
            by[r.surah, default: []].append(r)
        }
        return order.map { SurahGroup(surah: $0, ranges: by[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(groups, id: \.surah) { g in
                Text("سورة \(Quran.arabic(g.surah))").font(.arabic(26))
                Text("الآيات " + g.arabicRanges).font(.arabic(17))
                Text(g.latinRanges).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct SectionTitle: View {
    let text: String
    var count: Int? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.title3.weight(.semibold))
            if let count { Text("\(count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(.top, 8)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Wraps pills onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct Pill: View {
    let text: String
    var count: Int? = nil
    var strong = false
    var body: some View {
        HStack(spacing: 5) {
            Text(text)
            if let count { Text("\(count)").font(.caption2.monospacedDigit()).opacity(0.7) }
        }
        .font(.subheadline.weight(strong ? .semibold : .regular))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(strong ? Palette.accent.opacity(0.18) : Palette.soft, in: Capsule())
        .foregroundStyle(Palette.accent)
    }
}

struct LoadingView: View {
    var text = "Loading…"
    var body: some View {
        ProgressView(text).frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// Lists of points with a dot, used for objectives and takeaways.
struct BulletList: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Palette.accent)
                    Text(s)
                }
            }
        }
    }
}
