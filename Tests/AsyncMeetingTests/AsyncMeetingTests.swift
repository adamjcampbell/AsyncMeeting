import Testing
import AsyncMeeting

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
    func testTimeout() async throws {
        let meeting = AsyncMeeting(timeout: .nanoseconds(1))

        await #expect(throws: AsyncMeeting.MeetingError.timeout) {
            try await meeting.rendezvous()
        }
    }
}
