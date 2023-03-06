// LiveActivityManager.swift

import Foundation
import ActivityKit

@available(iOS 16.2, *)
class LiveActivityManager {
    enum LiveActivityManagerError: Error {
        case failedToGetId
    }
    
    private init() {}
    
    @discardableResult static func startActivity(
        messageAttributes: MessageAttributes,
        contentState: MessageAttributes.ContentState
    ) -> String {
        var activity: Activity<MessageAttributes>?
        
        do {
            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            activity = try Activity.request(
                attributes: messageAttributes,
                content: activityContent,
                pushType: nil
            )
            
            log("Started live activity")
            
            guard let id = activity?.id else { throw LiveActivityManagerError.failedToGetId }
            return id
        } catch {
            log("Error starting activity: \(error)")
            return ""
        }
    }
    
    static func updateActivity(with lastMessageText: String, id: String) async {
        let updatedContentState = MessageAttributes.ContentState(lastMessageText: lastMessageText)
        let activity = Activity<MessageAttributes>.activities.first(where: { $0.id == id })
        let updatedActivityContent = ActivityContent(state: updatedContentState, staleDate: nil)
        await activity?.update(updatedActivityContent)
    }
    
    static func endAllActivities() async {
        log("Ended all activities")
        for activity in Activity<MessageAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    
    static func endActivity(_ id: String) async {
        log("Ended activity: \(id)")
        let activity = Activity<MessageAttributes>.activities.first(where: { $0.id == id })
        await activity?.end(nil, dismissalPolicy: .immediate)
    }
}
