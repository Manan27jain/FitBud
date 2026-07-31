import Foundation

/// Formats a duration with hour rollover: `m:ss` under an hour, `h:mm:ss` at
/// or past one hour. Use this for the total elapsed/workout time — a half
/// marathon routinely takes 2:25–2:45, and long runs from week 5 onward also
/// cross an hour.
func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}

/// Formats a short duration as `m:ss`, with no hour rollover. Use this for
/// pace (seconds per kilometre) and per-split durations, which never
/// legitimately reach an hour — a `7:34/km` pace must never become
/// `0:07:34`.
func formatPace(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    return String(format: "%d:%02d", total / 60, total % 60)
}
