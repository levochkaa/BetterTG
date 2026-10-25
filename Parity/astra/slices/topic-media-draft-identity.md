# Topic media draft identity slice

- **P0 flow:** thread-scoped composer media ownership from pre-Liquid/current `ChatInterfaceState` and
  `ChatControllerMediaRecording`, adapted to Codable actors + TDLibKit rather than Postbox/SignalKit.
- Implemented: stable account/chat/full-topic key; four version-tolerant manifests; durable one-time legacy policy; exact restore,
  deduplication, enqueue, discard, recording handoff and resolution routing; draft-UUID outcome names; voice registration barrier;
  account/topic coordinator snapshots; stale account restore/promote guards; recorder receives the immutable destination.
- Proof: warning-free `.build/logs/xcodebuild/build-Debug-20260831-065904-41355-13754.log`; terminal probe files and run metadata
  `.build/ui-probe-evidence/topic-draft-key-*`; PID 41675 alive after proof, Simulator booted.
- Deferred: resolved network send context, topic text drafts/dirty generations, closed-topic write permission, exact returned-topic
  assertions, then attachments/voice/video UI enablement and topic-aware Forward/all-messages headers.
