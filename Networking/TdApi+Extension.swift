// TdApi+Extension.swift

import Foundation
import TDLibKit

extension TdApi {
    static var shared = TdApi(client: TdClientImpl(completionQueue: .global()))
    private static let logger = Logger(label: "Updates")

    // swiftlint:disable function_body_length
    func startTdLibUpdateHandler() {
        client.run { data in
            do {
                let update = try TdApi.shared.decoder.decode(Update.self, from: data)

                switch update {
                    case let .updateAuthorizationState(updateAuthorizationState):
                        switch updateAuthorizationState.authorizationState {
                            case .authorizationStateWaitTdlibParameters:
                                Task {
                                    var url = try FileManager.default.url(
                                        for: .applicationSupportDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil,
                                        create: true)
                                    let dir = url.path()
                                    url.append(path: "td")

                                    _ = try await self.setTdlibParameters(parameters: TdlibParameters(
                                        apiHash: Secret.apiHash,
                                        apiId: Secret.apiId,
                                        applicationVersion: SystemUtils.info(key: "CFBundleShortVersionString"),
                                        databaseDirectory: dir,
                                        deviceModel: await SystemUtils.getDeviceModel(),
                                        enableStorageOptimizer: true,
                                        filesDirectory: dir,
                                        ignoreFileNames: false,
                                        systemLanguageCode: "en-US",
                                        systemVersion: SystemUtils.osVersion,
                                        useChatInfoDatabase: true,
                                        useFileDatabase: true,
                                        useMessageDatabase: true,
                                        useSecretChats: true,
                                        useTestDc: false
                                    ))
                                }
                            case .authorizationStateWaitEncryptionKey:
                                Task {
                                    try? await self.checkDatabaseEncryptionKey(encryptionKey: Data())
                                }
                            case .authorizationStateReady:
                                Task {
                                    _ = try await self.loadChats(chatList: .chatListMain, limit: 10)
                                    _ = try await self.loadChats(chatList: .chatListArchive, limit: 10)
                                }
                            case .authorizationStateClosed:
                                TdApi.shared = TdApi(client: TdClientImpl(completionQueue: .global()))
                                TdApi.shared.startTdLibUpdateHandler()
                            default:
                                break
                        }
                    default:
                        break
                }
            } catch {
                guard let tdError = error as? TDLibKit.Error else { return }
                TdApi.logger.log("Code: \(tdError.code), message: \(tdError.message)", level: .error)
            }
        }
    }
}
