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
            RichNotificationPreviewProbe.runIfRequested()
            RichNotificationMediaStoreProbe.runIfRequested()
            TdUpdateSourceProbe.runDebugProbeIfRequested()
            LoginAuthorizationProbe.runDebugProbeIfRequested()
            MediaDraftOutcomeProbe.runDebugProbeIfRequested()
            ChatComposerEditProbe.runDebugProbeIfRequested()
            ComposerTextProbe.runDebugProbeIfRequested()
            ContextMenuInteractionProbe.runDebugProbeIfRequested()
            ChatComposerRestorationProbe.runDebugProbeIfRequested()
            ChatClientRestorationProbe.runDebugProbeIfRequested()
            ChatViewportRestorationProbe.runDebugProbeIfRequested()
            MessageTextSpoilerProbe.runDebugProbeIfRequested()
            TelegramLinkRouterProbe.runDebugProbeIfRequested()
            MessageDeliveryProbe.runIfRequested()
            ChatUpdateDeliveryProbe.runDebugProbeIfRequested()
            ChatListActionAuthorityProbe.runDebugProbeIfRequested()
            FolderFlowSessionProbe.runDebugProbeIfRequested()
            RootListAuthorityProbe.runDebugProbeIfRequested()
            RootScopeSettingsLoadingProbe.runDebugProbeIfRequested()
            PeerProfileInfoPermissionProbe.runDebugProbeIfRequested()
            PeerProfileEditSessionProbe.runIfRequested()
            PeerProfileRestorationProbe.runIfRequested()
            PeerProfileMembersRestorationProbe.runIfRequested()
            PeerProfileHistoryRequestProbe.runDebugProbeIfRequested()
            MessagePollInteractionStore.runDebugSubmissionProbeIfRequested()
            NavigationClientRestorationProbe.runDebugProbeIfRequested()
            ForumTopicsRestorationProbe.runDebugProbeIfRequested()
            VoiceNoteFinalizationProbe.runDebugProbeIfRequested()
            SendDraftRelocationProbe.runDebugProbeIfRequested()
            TDLibMediaUpdateStreamsProbe.runDebugProbeIfRequested()
            GalleryPictureInPictureCoordinator.runDebugProbeIfRequested()
            MediaDraftCodingProbe.runIfRequested()
            VoiceNoteCodec.runDebugProbeIfRequested()
            VoiceRecordingDraftPreservation.runDebugProbeIfRequested()
            VideoNoteAssetWriter.runDebugProbeIfRequested()
            VideoNoteCaptureSession.runCameraSwitchProbeIfRequested()
            VideoNoteFinishProbe.runDebugProbeIfRequested()
            VideoNoteSubmissionOwnershipProbe.runDebugProbeIfRequested()
            VideoNotePreservationProbe.runDebugProbeIfRequested()
            VideoNoteFileStore.runDebugProbeIfRequested()
            VideoNoteSegmentComposer.runDebugProbeIfRequested()
            VideoNoteRecordingDraftStore.runDebugProbeIfRequested()
            StoryViewerProbe.runIfRequested()
            ChatStatusPanelProbe.runIfRequested()
            ChatActionBarProbe.runIfRequested()
            ChatEmptyStateProbe.runIfRequested()
            PinnedMessageSelectionProbe.runIfRequested()
            ChatUnreadDividerProbe.runIfRequested()
            MessageTextBlocksProbe.runIfRequested()
            ChatListRowIconsProbe.runIfRequested()
            ChatTitleIconsProbe.runIfRequested()
            MessageStatusLineProbe.runIfRequested()
            MessageReadReportProbe.runIfRequested()
            MessageDeleteRowProbe.runIfRequested()
            MessageEntityMenuProbe.runIfRequested()
            MessageEntityMenuProbe.openHashtagSearchIfRequested()
            SendAsProbe.openIfRequested()
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
        VideoSendGenerationCoordinator.shared.start()
        AppLocalization.shared.start()
        AvatarColorPalette.shared.start()
        PushRelayCoordinator.shared.start()
        RichNotificationCacheCoordinator.shared.start()
        LiveLocationManager.shared.start()
        AttachmentMenuBotStore.shared.start()
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

    /// Info.plist's orientations, or the one a Web App locked (`web_app_toggle_orientation_lock`).
    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        WebAppOrientationLock.supportedOrientations
    }

    // MARK: Private

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.18)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.35)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .systemBlue
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
        window.semanticContentAttribute = AppLocalization.shared.isRTL ? .forceRightToLeft : .forceLeftToRight
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
            ServiceMessageTextProbe.runIfRequested()
            VoicePlaybackHeaderProbe.runIfRequested(in: window)
            SecretMediaPreviewProbe.runIfRequested(in: window)
            MusicPlayerProbe.runIfRequested(in: window)
            LocationViewerProbe.runIfRequested(in: window)
            PhotoCropProbe.runIfRequested(in: window)
            PollAttachProbe.runIfRequested(in: window)
            ContactFormatProbe.runIfRequested(in: window)
            PollMediaGalleryProbe.runIfRequested(in: window)
            BotButtonsProbe.runIfRequested(in: window)
            VideoEditProbe.runIfRequested(in: window)
            StoryViewerUIProbe.runIfRequested(in: window)
            StickerPeekProbe.runIfRequested(in: window)
            WebAppProbe.runIfRequested(in: window)
            WebAppLaunchProbe.runIfRequested(in: window)
            ChecklistTaskMenuProbe.runIfRequested(in: window)
            RaiseToListenProbe.runIfRequested(in: window)
            MessageMetadataDebugProbe.runIfRequested(in: window)
            MessageForwardingDebugProbe.runIfRequested(in: window)
            MessageReactionDebugProbe.runIfRequested(in: window)
            PinnedMessageDebugProbe.runIfRequested(in: window)
            ForumTopicDebugProbe.runIfRequested(in: window)
            ContextMenuLiquidMorphProbe.runIfRequested(in: window)
            TelegramClassicNavigationChromeProbe.runIfRequested(in: window)
        #endif

        for context in connectionOptions.urlContexts {
            TelegramLinkRouter.shared.handle(context.url, from: window.rootViewController)
        }
        for activity in connectionOptions.userActivities {
            if let url = activity.webpageURL {
                TelegramLinkRouter.shared.handle(url, from: window.rootViewController)
            }
        }

        if let response = connectionOptions.notificationResponse {
            Task {
                await PushRelayCoordinator.shared.handleNotificationResponse(response)
            }
        }
    }

    func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            TelegramLinkRouter.shared.handle(context.url, from: window?.rootViewController)
        }
    }

    func scene(_: UIScene, continue userActivity: NSUserActivity) {
        if let url = userActivity.webpageURL {
            TelegramLinkRouter.shared.handle(url, from: window?.rootViewController)
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
            .lazy
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        log("NSE diagnostic: event=\(entry.event)\(fields.isEmpty ? "" : ",\(fields)")")
    }
}
