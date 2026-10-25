# September 6 forum idle-scroll regression

The user reproduced continuous jumping with search hidden. A 12-second recording and six snapshots
confirmed about 80pt of visible movement despite unchanged accessibility row frames. LLDB caught
repeated 44pt additive table-bounds spring animations during diffable updates. Two mechanisms fed
the regression: the table's overridden content size conflicted with UIKit's update geometry, and
`updateForumTopic` requested `getForumTopic`, whose response emits another `updateForumTopic`.

Forum positioning now follows the chat list: set the initial offset once and snap only at drag end.
A native footer reserves search travel for short lists without overriding content size. Incoming
topic fields are applied directly; pin, inbox-read or draft-date changes fetch the missing full-topic
order/unread count only after those fields have been updated, so the echoed event cannot refetch.
Full responses merge and sort in a single publication.

`build-Debug-20260906-021227-74509-29734.log` passed with zero warnings. The fix was installed on the
same simulator as PID 74854, and the user confirmed the jumping was gone. Baseline video, pixel
measurements and debugger stacks are in `forum-jump` under the simulator evidence directory above.
