# AI coaching smoke test

A manual, real-network check to run once by hand, on a real watch, after
rotating the OpenAI key. Nothing here runs in CI: it costs real API calls and
needs a physical Apple Watch on a wrist with a phone nearby. The automated
suite and the DEBUG demo run (`DemoAIProvider`, simulator-only) cover
everything else; this is the one pass that exercises the live model.

1. Create `FitBud Watch App/Resources/Secrets.plist` from `Secrets.example.plist`
   and paste in the rotated key.
2. Confirm `git status` does **not** list it.
3. Build and run. Open Settings and confirm the key row reads "API key
   configured" in green.
4. Start a real run with the watch on the wrist and a phone nearby.
5. Confirm the opening line arrives within ~10s and is specific to today's
   session — it should name the session and the target zone, not generic
   encouragement.
6. Confirm a live cue arrives at a walk break referencing real splits.
7. End the run and confirm the summary carries an analysis.
8. Note the elapsed time between tapping Start and the opening line
   appearing — if it exceeds ~10s, switch the model constant to
   `gpt-5-nano`.
