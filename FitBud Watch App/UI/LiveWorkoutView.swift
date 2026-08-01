import SwiftUI

/// The live workout screen: five pages driven by the Digital Crown.
///
/// Selection starts at `.effort`, so Controls sit one turn *up* and the data
/// pages fan out below — the vertical analogue of Apple placing controls to the
/// left of the metrics.
struct LiveWorkoutView: View {
    let model: WorkoutSessionModel

    private enum Page: Hashable {
        case controls, effort, zones, metrics, splits
    }

    @State private var page: Page = .effort

    var body: some View {
        TabView(selection: $page) {
            ControlsPage(model: model).tag(Page.controls)
            EffortPage(model: model).tag(Page.effort)
            ZonesPage(model: model).tag(Page.zones)
            MetricsPage(model: model).tag(Page.metrics)
            SplitsPage(model: model).tag(Page.splits)
        }
        .tabViewStyle(.verticalPage)
        // Spec §5: SF Rounded throughout. Set once here so all five pages
        // inherit it — Controls and Splits were largely still on the default
        // face, and per-page `design:` arguments had drifted apart.
        .fontDesign(.rounded)
        .navigationBarBackButtonHidden(true)
    }
}
