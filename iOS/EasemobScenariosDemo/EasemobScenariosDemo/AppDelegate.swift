//
//  AppDelegate.swift
//  EasemobScenariosDemo
//
//  Created by 朱继超 on 2024/8/2.
//

import EaseChatUIKit
import HyphenateChat
import UserNotifications
import SwiftFFDBHotFix

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
        
    @UserDefault("EaseChatDemoPreferencesTheme", defaultValue: 1) var theme: UInt
    
    @UserDefault("EaseMobChatMessageTranslation", defaultValue: true) var enableTranslation: Bool
    
    @UserDefault("EaseMobChatMessageReaction", defaultValue: true) var messageReaction: Bool
    
    @UserDefault("EaseMobChatCreateMessageThread", defaultValue: true) var messageThread: Bool
    
    @UserDefault("EaseChatDemoPreferencesBlock", defaultValue: true) var block: Bool
    
    @UserDefault("EaseChatDemoUserToken", defaultValue: "") private var token
    
    @UserDefault("EaseScenariosDemoPhone", defaultValue: "") private var phone
    

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        self.setupEaseChatUIKit()
        self.setupEaseChatUIKitConfig()
        self.registerRemoteNotification()
        return true
    }
    
    private func setupEaseChatUIKit() {
        let options = ChatOptions(appkey: AppKey)
//        options.includeSendMessageInMessageListener = true
        options.isAutoLogin = true
        options.enableConsoleLog = true
        options.usingHttpsOnly = true
        options.deleteMessagesOnLeaveGroup = false
        options.enableDeliveryAck = true
        options.enableRequireReadAck = true
        //Simulator can't use APNS, so we need to judge whether it is a real machine.
        #if DEBUG
        options.apnsCertName = "aps-scenario-push-dev"
        #else
        options.apnsCertName = "apns-scenario-push"
        #endif
        //Set up EaseChatUIKit
        _ = EaseChatUIKitClient.shared.setup(option: options)
        EaseChatUIKitClient.shared.registerUserStateListener(self)
        _ = PresenceManager.shared
    }
    
    private func setupEaseChatUIKitConfig() {
        //Set the theme of the chat demo UI.
        if self.theme == 0 {
            Appearance.avatarRadius = .extraSmall
            Appearance.chat.inputBarCorner = .extraSmall
            Appearance.alertStyle = .small
            Appearance.chat.bubbleStyle = .withArrow
        } else {
            Appearance.avatarRadius = .large
            Appearance.chat.inputBarCorner = .large
            Appearance.alertStyle = .large
            Appearance.chat.bubbleStyle = .withMultiCorner
        }
        Appearance.hiddenPresence = false
        Appearance.chat.enableTyping = true
        Appearance.contact.enableBlock = self.block
        //Enable message translation
        Appearance.chat.enableTranslation = self.enableTranslation
        if Appearance.chat.enableTranslation {
            let preferredLanguage = NSLocale.preferredLanguages[0]
            if preferredLanguage.starts(with: "zh-Hans") || preferredLanguage.starts(with: "zh-Hant") {
                Appearance.chat.targetLanguage = .Chinese
            } else {
                Appearance.chat.targetLanguage = .English
            }
        }
        //Whether show message topic or not.
        if self.messageThread {
            Appearance.chat.contentStyle.append(.withMessageThread)
        }
        //Whether show message reaction or not.
        if self.messageReaction {
            Appearance.chat.contentStyle.append(.withMessageReaction)
        }
        //Notice: - Feature identify can't changed, it's used to identify feature action.
        
        //Register custom components
        ComponentsRegister.shared.ConversationCell = MineConversationCell.self
        ComponentsRegister.shared.MessagesViewModel = MineMessageListViewModel.self
        ComponentsRegister.shared.ConversationsController = MineConversationsController.self
        ComponentsRegister.shared.MessageViewController = MineMessageListViewController.self
    }
    
    

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        
    }

    private func registerRemoteNotification() {
        //Simulator can't use APNS, so we need to judge whether it is a real machine.
        #if !targetEnvironment(simulator)
        
        UIApplication.shared.applicationIconBadgeNumber = 0
        EMLocalNotificationManager.shared().launch(with: self)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
            // Handle granted and error here
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        #endif
    }

}

extension AppDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        ChatClient.shared().registerForRemoteNotifications(withDeviceToken: deviceToken) { error in
            if error != nil {
                consoleLogInfo("Register for remote notification error:\(error?.errorDescription ?? "")", type: .error)
            }
        }
        
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        DialogManager.shared.showAlert(title: "Register notification failed", content: error.localizedDescription, showCancel: true, showConfirm: true) { _ in
            
        }
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        ChatClient.shared().application(application, didReceiveRemoteNotification: userInfo)
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        self.cancelMatch()
        
        if EaseMob1v1CallKit.shared.onCalling {
            EaseMob1v1CallKit.shared.endCall(reason: "杀进程退出")
        }
        EaseMob1v1CallKit.shared.cancelMatchNotify()
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        
        backgroundTask = application.beginBackgroundTask(expirationHandler: {
            // 清理代码
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        })
        
    }
    
    func cancelMatch() {
        
        EasemobBusinessRequest.shared.sendDELETERequest(api: .cancelMatch(self.phone), params: [:]) { result, error in
            
        }
    }
}


extension AppDelegate: EMLocalNotificationDelegate {
    func emGetNotificationMessage(_ notification: UNNotification, state: EMNotificationState) {

        if notification.request.trigger is UNPushNotificationTrigger {
            //apns
            DialogManager.shared.showAlert(title: state == .willPresentNotification ? "Push Arrive":"Push Click", content: notification.request.content.title, showCancel: false, showConfirm: true) { _ in
                
            }
        } else {
            //local notification
            if let userInfo = notification.request.content.userInfo as? [String: Any] {
                DialogManager.shared.showAlert(title: state == .willPresentNotification ? "Local Arrive":"Local Click", content: notification.request.content.title, showCancel: false, showConfirm: true) { _ in
                    
                }
            }
        }
        if state == .didReceiveNotificationResponse {
            //click notification enter app
        } else {
            //notification will dispaly
        }
    }
}

//MARK: - UserStateChangedListener
extension AppDelegate: UserStateChangedListener {
    
    private func logoutUser() {
        EaseChatUIKitClient.shared.logout(unbindNotificationDeviceToken: true) { error in
            if error != nil {
                consoleLogInfo("Logout failed:\(error?.errorDescription ?? "")", type: .error)
            }
        }
    }
    
    func onUserTokenDidExpired() {
        NotificationCenter.default.post(name: Notification.Name(rawValue: backLoginPage), object: nil)
    }
    
    func onUserLoginOtherDevice(device: String) {
        self.logoutUser()
        NotificationCenter.default.post(name: Notification.Name(rawValue: backLoginPage), object: nil)
    }
    
    func onUserTokenWillExpired() {
        //Notice: - If you want to refresh token, you need to implement the logic in this method.
//        EaseChatUIKitClient.shared.refreshToken(token: token)
    }
    
    func onSocketConnectionStateChanged(state: EaseChatUIKit.ConnectionState) {
        //Socket state monitor network
        if state == .connected {
            NotificationCenter.default.post(name: Notification.Name(rawValue: connectionSuccessful), object: nil)
        } else {
            NotificationCenter.default.post(name: Notification.Name(rawValue: connectionFailed), object: nil)
        }
    }
    
    func userAccountDidRemoved() {
        self.logoutUser()
        NotificationCenter.default.post(name: Notification.Name(rawValue: backLoginPage), object: nil)
    }
    
    func userDidForbidden() {
        self.logoutUser()
        NotificationCenter.default.post(name: Notification.Name(rawValue: backLoginPage), object: nil)
    }
    
    func userAccountDidForcedToLogout(error: EaseChatUIKit.ChatError?) {
        self.logoutUser()
        NotificationCenter.default.post(name: Notification.Name(rawValue: backLoginPage), object: nil)
    }
    
    func onUserAutoLoginCompletion(error: EaseChatUIKit.ChatError?) {
//        if error != nil {
//            NotificationCenter.default.post(name: Notification.Name(rawValue: backLoginPage), object: nil)
//        } else {
//            self.token = ChatClient.shared().accessUserToken ?? ""
//            ChatClient.shared().pushManager?.syncSilentModeConversations(fromServerCompletion: { error in
//                
//            })
//            if let groups = ChatClient.shared().groupManager?.getJoinedGroups() {
//                var profiles = [EaseChatProfile]()
//                for group in groups {
//                    let profile = EaseChatProfile()
//                    profile.id = group.groupId
//                    profile.nickname = group.groupName
//                    profile.avatarURL = group.settings.ext
//                    profiles.append(profile)
//                    profile.insert()
//                }
//                EaseChatUIKitContext.shared?.updateCaches(type: .group, profiles: profiles)
//            }
//            if let users = EaseChatUIKitContext.shared?.userCache {
//                for user in users.values {
//                    EaseChatUIKitContext.shared?.userCache?[user.id]?.remark = ChatClient.shared().contactManager?.getContact(user.id)?.remark ?? ""
//                }
//            }
//            NotificationCenter.default.post(name: Notification.Name(loginSuccessfulSwitchMainPage), object: nil)
//        }
    }
    
}
