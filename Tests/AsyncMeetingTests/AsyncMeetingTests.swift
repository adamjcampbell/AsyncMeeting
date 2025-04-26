@testable import AsyncMeeting
import ConcurrencyExtras
import Testing

struct AsyncMeetingTests {
    actor TestActor {
        var testInt = 0

        func increment() {
            testInt += 1
        }
    }

    @Test("Test a rendezvous with no work performed")
    func testRendezvousNoWorkPerformed() async throws {
        let actor = TestActor()
        let meeting = AsyncMeeting()

        let task = Task {
            try await meeting.rendezvous()
            await actor.increment()
        }

        await #expect(actor.testInt == 0)

        try await meeting.rendezvous()
        try await task.value

        await #expect(actor.testInt == 1)
    }

    @Test("Test rendezvous with work performed")
    func testRendezvousWorkPerformed() async throws {
        let actor = TestActor()
        let meeting = AsyncMeeting()

        let task = Task {
            try await meeting.rendezvous {
                await actor.increment()
            }
        }

        await #expect(actor.testInt == 0)

        try await meeting.rendezvous()
        await #expect(actor.testInt == 1)

        try await task.value
    }

    @Test("Timeout")
    func timeout() async throws {
        let meeting = AsyncMeeting(timeout: .nanoseconds(1))

        await #expect(throws: AsyncMeeting.MeetingError.timeout) {
            try await meeting.rendezvous()
        }
    }

    @Test("Cancellation without a continuation set")
    func cancellationWithNoContinuationSet() async throws {
        await withMainSerialExecutor {
            let meeting = AsyncMeeting()

            let task = Task { try await meeting.rendezvous() }

            meeting.state.withLock { state in
                #expect(state.continuation == nil)
            }

            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }

    @Test("Cancellation with a continuation set")
    func cancellationWithContinuationSet() async throws {
        await withMainSerialExecutor {
            let meeting = AsyncMeeting()

            let task = Task { try await meeting.rendezvous() }

            // Ensure all work is performed
            await Task.megaYield()

            meeting.state.withLock { state in
                #expect(state.continuation != nil)
            }

            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }
}
