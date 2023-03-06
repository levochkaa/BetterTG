// BetterWidgetLiveActivity.swift

import ActivityKit
import WidgetKit
import SwiftUI

struct BetterWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MessageAttributes.self) { _ in
            EmptyView()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    photo(context: context)
                        .frame(width: 64, height: 64)
                }
                .contentMargins(.top, 20)
                
                DynamicIslandExpandedRegion(.center) {
                    HStack(alignment: .center, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.attributes.name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundColor(.gray)
                            
                            Text(context.state.lastMessageText)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                        }
                        .lineLimit(1)
                        
                        Spacer()
                    }
                }
            } compactLeading: {
                photo(context: context)
                    .frame(width: 24, height: 24)
            } compactTrailing: {
                appIcon
            } minimal: {
                appIcon
            }
//            .widgetURL(URL(string: "https://www.apple.com"))
        }
    }
    
    @ViewBuilder var appIcon: some View {
        Image("Icon")
            .resizable()
            .frame(width: 24, height: 24)
            .clipShape(Circle())
    }
    
    @ViewBuilder func photo(context: ActivityViewContext<MessageAttributes>) -> some View {
        if let imagePath = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: "group.com.levochkaaa.BetterTGWidget"
           )?.appending(path: context.attributes.avatarId).path(),
           let uiImage = UIImage(contentsOfFile: imagePath) {
            Image(uiImage: uiImage)
                .resizable()
                .clipShape(Circle())
        }
    }
}

@available(iOS 16.2, *)
struct BetterWidgetLiveActivity_Previews: PreviewProvider {
    static let attributes = MessageAttributes(name: "name", avatarId: "path/")
    static let contentState = MessageAttributes.ContentState(lastMessageText: "text here")
    
    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Island Compact")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Island Expanded")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Minimal")
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Notification")
    }
}
