// BetterTGApp.swift

import AppIntents
import UIKit

// MARK: - AppDelegate

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: Internal

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        FFmpegCapabilities.assertRequiredCodecsAvailable()
        #if DEBUG
            RichNotificationTargetProbe.runIfRequested()
            RichNotificationSessionLifetimeProbe.runIfRequested()
            RichNotificationRequestProbe.runIfRequested()
            TdUpdateSourceProbe.runDebugProbeIfRequested()
            LoginAuthorizationProbe.runDebugProbeIfRequested()
            MediaDraftOutcomeProbe.runDebugProbeIfRequested()
            ChatComposerEditProbe.runDebugProbeIfRequested()
            ComposerTextProbe.runDebugProbeIfRequested()
            ChatComposerRestorationProbe.runDebugProbeIfRequested()
            ChatClientRestorationProbe.runDebugProbeIfRequested()
            ChatViewportRestorationProbe.runDebugProbeIfRequested()
            MessageTextSpoilerProbe.runDebugProbeIfRequested()
            MessageDeliveryProbe.runIfRequested()
            ChatUpdateDeliveryProbe.runDebugProbeIfRequested()
            ChatListActionAuthorityProbe.runDebugProbeIfRequested()
            FolderFlowSessionProbe.runDebugProbeIfRequested()
            RootListAuthorityProbe.runDebugProbeIfRequested()
            RootChatInsertionProbe.runDebugProbeIfRequested()
            RootScopeSettingsLoadingProbe.runDebugProbeIfRequested()
            RootChatProjectionProbe.runDebugProbeIfRequested()
            PeerProfileInfoPermissionProbe.runDebugProbeIfRequested()
            PeerProfileEditSessionProbe.runIfRequested()
            PeerProfileRestorationProbe.runIfRequested()
            PeerProfileMembersRestorationProbe.runIfRequested()
            PeerProfileHistoryRequestProbe.runDebugProbeIfRequested()
            MessagePollInteractionStore.runDebugSubmissionProbeIfRequested()
            NavigationClientRestorationProbe.runDebugProbeIfRequested()
            ForumTopicsRestorationProbe.runDebugProbeIfRequested()
            ClassicNavigationProbe.runDebugProbeIfRequested()
            VoiceNoteFinalizationProbe.runDebugProbeIfRequested()
            SendDraftRelocationProbe.runDebugProbeIfRequested()
            TDLibMediaUpdateStreamsProbe.runDebugProbeIfRequested()
            GalleryPictureInPictureCoordinator.runDebugProbeIfRequested()
            VoiceNoteCodec.runDebugProbeIfRequested()
            VoiceRecordingDraftPreservation.runDebugProbeIfRequested()
            VideoNoteAssetWriter.runDebugProbeIfRequested()
            VideoNoteFinishProbe.runDebugProbeIfRequested()
            VideoNoteSubmissionOwnershipProbe.runDebugProbeIfRequested()
            VideoNotePreservationProbe.runDebugProbeIfRequested()
            VideoNoteFileStore.runDebugProbeIfRequested()
            VideoNoteSegmentComposer.runDebugProbeIfRequested()
            VideoNoteRecordingDraftStore.runDebugProbeIfRequested()
            TDLibVODRangeSource.runDebugProbeIfRequested()
            TDLibVODFFmpegLookahead.runDebugProbeIfRequested()
            TDLibVODFFmpegDecoder.runDebugProbeIfRequested()
            FFmpegAnimatedVideoView.runDebugProbeIfRequested()
            AnimatedFileDownloadProbe.runDebugProbeIfRequested()
            TDLibVODResourceLoaderSession.runDebugProbeIfRequested()
            GalleryVideoPlaybackOwner.runDebugProbeIfRequested()
        #endif
        VoiceNoteDraftCoordinator.shared.start()
        VideoNoteDraftCoordinator.shared.start()
        AvatarColorPalette.shared.start()
        PushRelayCoordinator.shared.start()
        RichNotificationCacheCoordinator.shared.start()
        TDLib.shared.startTdLibUpdateHandler()
        logPendingRichNotificationDiagnostics()
        configureAppearance()
        return true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        PushRelayCoordinator.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
    ) {
        PushRelayCoordinator.shared.didFailToRegisterForRemoteNotifications(error)
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
    ) {
        Task {
            let changed = await PushRelayCoordinator.shared.handleBackgroundNotification(userInfo: userInfo)
            completionHandler(changed ? .newData : .noData)
        }
    }

    /// Do not use this callback for lifecycle work. BetterTG uses scenes; keep background
    /// ownership in `SceneDelegate.sceneDidEnterBackground(_:)`. This log verifies runtime dispatch.
    func applicationDidEnterBackground(_: UIApplication) {
        log("Lifecycle callback: AppDelegate.applicationDidEnterBackground")
    }

    /// Do not use this callback for lifecycle work. BetterTG uses scenes; keep foreground
    /// ownership in `SceneDelegate.sceneWillEnterForeground(_:)`. This log verifies runtime dispatch.
    func applicationWillEnterForeground(_: UIApplication) {
        log("Lifecycle callback: AppDelegate.applicationWillEnterForeground")
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role,
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // MARK: Private

    private func configureAppearance() {
        ClassicNavigation.applyAppearance(to: UINavigationBar.appearance())
    }
}

// MARK: - SceneDelegate

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Utils.screen = windowScene.screen

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = AppAppearance.current.userInterfaceStyle
        window.rootViewController = RootViewController(rootVM: .shared)
        window.makeKeyAndVisible()
        self.window = window
        #if DEBUG
            MediaGalleryTransitionTarget.runDebugProbeIfRequested(in: window)
            VideoNoteHoldProbe.runIfRequested(in: window)
            TDImageLoadingProbe.runIfRequested()
            MediaRevealProbe.runIfRequested(in: window)
            ProfileMediaRevealProbe.runIfRequested(in: window)
            FFmpegSampleBufferRenderer.runDebugProbeIfRequested(in: window)
            TDLibVODFFmpegSampleBufferPlayer.runDebugProbeIfRequested(in: window)
            MessageContentDebugProbe.runIfRequested(in: window)
            MessageMetadataDebugProbe.runIfRequested(in: window)
            MessageForwardingDebugProbe.runIfRequested(in: window)
            MessageReactionDebugProbe.runIfRequested(in: window)
            PinnedMessageDebugProbe.runIfRequested(in: window)
            ForumTopicDebugProbe.runIfRequested(in: window)
        #endif

        if let response = connectionOptions.notificationResponse {
            Task {
                await PushRelayCoordinator.shared.handleNotificationResponse(response)
            }
        }
    }

    func sceneDidEnterBackground(_: UIScene) {
        log("Lifecycle callback: SceneDelegate.sceneDidEnterBackground")
        TDLib.shared.releaseForNotificationService()
    }

    func sceneWillEnterForeground(_: UIScene) {
        log("Lifecycle callback: SceneDelegate.sceneWillEnterForeground")
        logPendingRichNotificationDiagnostics()
        TDLib.shared.resumeAfterNotificationService()
    }
}

private func logPendingRichNotificationDiagnostics() {
    for entry in RichNotificationDiagnostics.recentEntries() {
        let fields = entry.fields
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        log("NSE diagnostic: event=\(entry.event)\(fields.isEmpty ? "" : ",\(fields)")")
    }
}
