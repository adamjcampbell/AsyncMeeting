# AsyncMeeting
A package to synchronise async callers using the rendezvous pattern

## Motivation

Coordinating asynchronous code can be tricky, a rendezvous performs a
mutual signalling between two threads (or in this instance, tasks) to
ensure that two threads meet at a pre-defined common point.

This is useful for any application where you need to co-ordinate between
two async context. Commonly in tests but also applicable for use cases such
as coordinating with a stateful third party library.

## Test Example

Below is a simple observable model that loads a list of names. It has the
mutable state `isLoading` and `names` that we'd like to test before, during
and after the completion of the `load` function.  
We can inject the `fetchNames` function however being able to test for when
`isLoading` is true is fraught with racey behaviour.

```swift
@MainActor
@Observable
final class AttendeeListModel {
    var isLoading = false
    var names: [String] = []

    private let fetchNames: () async throws -> [String]

    init(fetchNames: @escaping () async throws -> [String]) {
        self.fetchNames = fetchNames
    }

    func load() async throws {
        isLoading = true
        defer { isLoading = false }

        names = try await fetchNames()
    }
}
```

One way to gain deterministic control over the execution of the test is to use
a rendezvous.  
Below we create an `AsyncMeeting` calling for a `rendezvous` in the injected
`fetchNames` function. We then test the initial state, before kicking off a
load task.  
We know the load task will wait until the rendezvous so we must then call
`rendezvous` ourselves. We pass a closure which will run during the suspension
in order to test our intermediate state.  
Finally we can await completion of the task and test the final state.

```swift
@MainActor
@Test("Test loading")
func testLoading() async throws {
    let meeting = AsyncMeeting()

    let model = AttendeeListModel(
        fetchNames: {
            // Wait until the test path calls rendezvous
            try await meeting.rendezvous()
            return ["Sarah", "Bobby", "Joe"]
        }
    )

    #expect(model.isLoading == false)
    #expect(model.names == [])

    let task = Task { try await model.load() }

    try await meeting.rendezvous { @MainActor in
        // Run expectations during suspension
        // to test intermediate state
        #expect(model.isLoading == true)
        #expect(model.names == [])
    }

    try await task.value

    #expect(model.isLoading == false)
    #expect(model.names == ["Sarah", "Bobby", "Joe"])
}
```

### Timeouts

If the coordination happens indirectly i.e. not called directly in the test, it
may be beneficial to use a timeout to prevent test deadlock.  
A timeout can be configured by passing a duration to `AsyncMeeting`.

```swift
let meeting = AsyncMeeting(duration: .seconds(1))
```

## Acknowledgements

Thanks to Nikolai Ruhe for creating [TaskMeeting](https://gist.github.com/NikolaiRuhe/c98005245d7b6e25328752cf0680675c)
an existing implementation of a rendezvous in Swift which inspired this package.

