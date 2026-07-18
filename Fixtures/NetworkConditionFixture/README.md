# Network Condition Fixture

This fixture verifies the simulator-control actions exposed by the `sipi-test`
harness. It displays `NWPathMonitor`, request, deep-link, push-notification, and
location results through stable accessibility identifiers.

Generate the Xcode project and install the app before running the saved test:

```bash
cd Fixtures/NetworkConditionFixture
xcodegen generate
xcodebuild -project NetworkConditionFixture.xcodeproj \
  -scheme NetworkConditionFixture \
  -sdk iphonesimulator \
  -derivedDataPath .derived-data build
xcrun simctl install booted \
  .derived-data/Build/Products/Debug-iphonesimulator/NetworkConditionFixture.app
cd ../..
sipi run-test \
  Fixtures/NetworkConditionFixture/.simpilot/tests/simulator-controls.json \
  --workspace Fixtures/NetworkConditionFixture/.simpilot
```

The saved test grants and then resets location permission. On the first run it
also accepts the English or Japanese notification and custom-URL confirmation
buttons when present. If notifications were previously denied, reset or erase
the fixture's Simulator state before rerunning the push step.

`network-error-message.json` uses a deliberately unreachable loopback endpoint
to prove that an actual request failure reaches the app's error UI. This is not
an offline-path simulation; use a provider-backed `network-condition` profile
when the test specifically requires `NWPathMonitor` to become unsatisfied.

Network profiles are deliberately not assumed. `sipi network-condition status`
must report an available explicitly installed provider before a test adds a
`network-condition` action.
