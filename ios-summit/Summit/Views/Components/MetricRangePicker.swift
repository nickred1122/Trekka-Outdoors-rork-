import SwiftUI

/// Segmented control that scopes every dashboard chart to a window.
struct MetricRangePicker: View {
    @Binding var selection: MetricRange
    /// Only the ranges the underlying data can actually support.
    var ranges: [MetricRange] = MetricRange.allCases
    var usesFullTitles: Bool = false

    @Namespace private var namespace

    /// The selection as drawn — a longer range than the data supports falls back
    /// to the widest one that is offered.
    private var resolved: MetricRange { selection.clamped(to: ranges) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ranges) { range in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selection = range
                    }
                } label: {
                    Text(usesFullTitles ? range.title : range.shortTitle)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(resolved == range ? Theme.accent : Theme.textPrimary.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(.rect)
                        .background {
                            if resolved == range {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Theme.accent.opacity(0.16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9)
                                            .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
                                    }
                                    .matchedGeometryEffect(id: "selectedRange", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(range.title)
                .accessibilityAddTraits(resolved == range ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(Theme.surface, in: .rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .animation(.snappy(duration: 0.25), value: ranges)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Granularity selector for a hand-picked date range.
///
/// A rolling preset carries its own granularity, but a range chosen by hand does
/// not — six weeks is legitimately readable day by day or week by week, and only
/// the person reading it knows which they wanted.
struct MetricBucketPicker: View {
    @Binding var selection: MetricBucket
    /// Only the granularities the span is long enough to support.
    var buckets: [MetricBucket]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(buckets) { bucket in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selection = bucket
                    }
                } label: {
                    Text(bucket.shortTitle)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(selection == bucket ? Theme.accent : Theme.textPrimary.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                        .background {
                            if selection == bucket {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.accent.opacity(0.16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
                                    }
                                    .matchedGeometryEffect(id: "selectedBucket", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bucket.title)
                .accessibilityAddTraits(selection == bucket ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.surface, in: .rect(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .animation(.snappy(duration: 0.25), value: buckets)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The whole window control: rolling presets, or an exact day or date range.
///
/// Presets and hand-picked dates are mutually exclusive, so only one of the two
/// is ever on screen and there is never a question of which the charts obey.
struct MetricWindowBar: View {
    @Binding var range: MetricRange
    @Binding var span: MetricSpan?
    var ranges: [MetricRange] = MetricRange.allCases
    var usesFullTitles: Bool = false
    /// Plain description of what is plotted, shown underneath. Empty hides it.
    var caption: String = ""
    /// As far back as the stored history reaches.
    var earliest: Date

    @State private var showsSheet = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if let active = span {
                    spanChip(active)
                } else {
                    MetricRangePicker(selection: $range, ranges: ranges, usesFullTitles: usesFullTitles)
                }
                calendarButton
            }
            // A hand-picked range keeps its granularity control, so picking exact
            // dates never costs you the ability to read them by day or by week.
            if let active = span, active.availableBuckets.count > 1 {
                MetricBucketPicker(
                    selection: bucketBinding(for: active),
                    buckets: active.availableBuckets
                )
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
            }
        }
        .animation(.snappy(duration: 0.28), value: span)
        .sheet(isPresented: $showsSheet) {
            DateWindowSheet(span: $span, earliest: earliest)
        }
    }

    /// Writes the chosen granularity back into the active span.
    private func bucketBinding(for active: MetricSpan) -> Binding<MetricBucket> {
        Binding(
            get: { active.resolvedBucket },
            set: { newValue in
                var updated = active
                updated.bucket = newValue
                span = updated
            }
        )
    }

    private var calendarButton: some View {
        Button {
            showsSheet = true
        } label: {
            Image(systemName: span == nil ? "calendar" : "calendar.badge.checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(span == nil ? Theme.textPrimary.opacity(0.6) : Theme.accent)
                .frame(width: 46, height: 46)
                .background(span == nil ? Theme.surface : Theme.accent.opacity(0.12), in: .rect(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(span == nil ? Theme.border : Theme.accent.opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick a day or date range")
    }

    private func spanChip(_ active: MetricSpan) -> some View {
        HStack(spacing: 8) {
            Button {
                showsSheet = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: active.isSingleDay ? "calendar.day.timeline.left" : "calendar")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(active.title)
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(active.subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                span = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to rolling windows")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
