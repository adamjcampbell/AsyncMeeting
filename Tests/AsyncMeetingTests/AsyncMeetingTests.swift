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
    func testRendezvousNoWorkPerformed() async {
        let actor = TestActor()
        let meeting = AsyncMeeting()

        let task = Task {
            await meeting.rendezvous()
            await actor.increment()
        }

        await #expect(actor.testInt == 0)

        await meeting.rendezvous()
        await task.value

        await #expect(actor.testInt == 1)
    }

    @Test("Test rendezvous with work performed")
    func testRendezvousWorkPerformed() async {
        let actor = TestActor()
        let meeting = AsyncMeeting()

        let task = Task {
            await meeting.rendezvous {
                await actor.increment()
            }
        }

        await #expect(actor.testInt == 0)

        await meeting.rendezvous()
        await #expect(actor.testInt == 1)

        await task.value
    }
}
