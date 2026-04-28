# ZoneTruth

A macOS/iOS workout analysis app that answers one question: **was this actually a Zone 2 session?**

It reads workout data from Apple Health or Strava, applies a policy-based heart-rate analyzer, and returns a plain-language verdict — pass, warning, or fail — with the reasons why.

---

## What it does

ZoneTruth analyzes a workout session's heart-rate data against a configurable Zone 2 policy. For each session it produces:

- **Verdict** — pass / warning / fail
- **Zone distribution** — what percentage of time was spent in each zone
- **HR stability** — standard deviation of the sanitized sample set
- **HR drift** — how much heart rate climbed from the first quarter to the last quarter of the session
- **Plain-language reasons** — what triggered the verdict
- **Recommendations** — what to adjust next time

The analyzer sanitizes data before judging: warm-up, cool-down, and abnormal spikes are excluded.

---

## Architecture

```
ZoneTruthCore          (pure domain logic, no Apple frameworks)
├── Models.swift       WorkoutInput, HeartRateSample, AnalysisResult, …
├── Analyzers.swift    WorkoutIntentAnalyzer, zone math, sanitization
└── SampleWorkoutCases.swift  labeled validation dataset

ZoneTruthApp           (platform adapters and SwiftUI shell)
├── HealthKitAdapter   reads workouts + HR samples from Apple Health
├── StravaAdapter      OAuth flow, token management, activity fetch
├── DataImport         composite repository, JSON import, app environment
├── ViewModels         WorkoutListViewModel (ObservableObject)
├── Views              list + detail SwiftUI views
└── ZoneTruthApp       @main, URL scheme handler
```

The core package has no dependencies on Apple frameworks — it can be tested on Linux and stays stable as adapters evolve.

---

## Data sources

ZoneTruth tries sources in priority order and uses the first one that returns data:

| Source | Status |
|---|---|
| Apple Health | Reads recent workouts + time-bounded HR samples via HealthKit |
| Strava | OAuth 2.0 login, activity list, heart-rate streams via Strava API |
| JSON import | Drop a `SampleData/workouts.json` file (see format below) |
| Preview samples | Built-in labeled cases used in tests and previews |

---

## Getting started

### Requirements

- Xcode 15+ or Swift 5.9+ toolchain
- macOS 14+ or iOS 17+ for Apple Health features

### Build and test

```bash
swift build
swift test
```

All 38 tests should pass. No credentials are required to run tests.

### Apple Health

Apple Health authorization is requested in-app via the **Request Apple Health Access** button. No configuration needed.

### Strava

Strava integration requires a registered API application.

1. Create an app at [strava.com/settings/api](https://www.strava.com/settings/api)
2. Set the **Authorization Callback Domain** to `zonetruth`
3. Fill in your credentials in `StravaAdapter.swift`:

```swift
private enum StravaCredentials {
    static let clientID: Int = 0          // ← your client ID
    static let clientSecret: String = ""  // ← your client secret
}
```

4. Register the `zonetruth://` URL scheme in your Xcode target's Info.plist

When credentials are set (`clientID != 0`), the app builds a Strava authorization URL and handles the OAuth callback automatically. The token is stored in `SampleData/strava-session.json` and refreshed transparently when it expires.

### JSON import

Drop a file at `SampleData/workouts.json` with this format:

```json
{
  "workouts": [
    {
      "workoutType": "running",
      "startDate": "2026-04-01T06:00:00Z",
      "endDate": "2026-04-01T07:00:00Z",
      "intent": "Zone 2",
      "heartRateSamples": [
        { "timestamp": "2026-04-01T06:05:00Z", "bpm": 118 },
        { "timestamp": "2026-04-01T06:10:00Z", "bpm": 121 }
      ]
    }
  ]
}
```

Valid `workoutType` values: `running`, `cycling`, `swimming`, `walking`, `strengthTraining`, `mixed`, `other`

Valid `intent` values: `"Zone 2"`, `"Activity / Skill"`, `"VO2 / Interval"`, `"Strength"`

---

## Analysis policy

The default policy (editable in `AnalysisPolicy.default`):

| Parameter | Default |
|---|---|
| Zone 2 range | 110 – 125 bpm |
| Zone 4 threshold | 141 bpm |
| Zone 5 threshold | 156 bpm |
| Warm-up exclusion | 5 min |
| Cool-down exclusion | 3 min |
| Minimum duration | 20 min |
| Minimum samples | 20 |
| Spike threshold | ±25 bpm from adjacent sample |

A session **passes** when Zone 2 time is high, leakage into Zone 3+ is low, HR stability is good, and HR drift is minimal. Warning and fail thresholds are tuned in `Analyzers.swift`.

---

## Project structure

```
Sources/
  ZoneTruthCore/       pure domain library
  ZoneTruthApp/        platform app target
Tests/
  ZoneTruthCoreTests/  analyzer and model tests
  ZoneTruthAppTests/   adapter, repository, and OAuth tests
SampleData/
  workouts.example.json        import format reference
  strava-session.example.json  session file format reference
memory/                        project notes and task log
```
