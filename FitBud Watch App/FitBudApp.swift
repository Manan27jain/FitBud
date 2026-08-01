//
//  FitBudApp.swift
//  FitBud Watch App
//
//  Created by MJ on 31/07/26.
//

import SwiftUI

@main
struct FitBud_Watch_AppApp: App {
    // Owned here, not in `RootView`, because `App` is created once per
    // process while a `Scene`'s views are recreated whenever watchOS tears
    // down and rebuilds the UI of an app it is keeping alive only because an
    // `HKWorkoutSession` is running — which is most of a long run. A
    // scene-owned model would be dropped mid-workout with its session still
    // live, orphaning it: nothing left to end it, watchOS allows only one
    // active session, and the next `start()` hangs. Hoisting ownership here
    // means a scene rebuild can no longer orphan the session.
    //
    // This does not cover process death: recovering a session that outlived
    // the process entirely needs `HKHealthStore.recoverActiveWorkoutSession()`,
    // deliberately deferred to Stage 2.
    @State private var model = WorkoutSessionModel()
    @State private var settings = CoachSettings()

    var body: some Scene {
        WindowGroup {
            RootView(model: model, settings: settings)
                .task {
                    model.configureCoach(
                        provider: settings.makeProvider(),
                        speaker: WatchCoachSpeaker(),
                        settings: settings
                    )
                }
        }
    }
}
