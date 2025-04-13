//
//  fullyhacksApp.swift
//  fullyhacks
//
//  Created by Yang Gao on 4/11/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
      
//      let providerFactory = AppCheckDebugProviderFactory()
//      AppCheck.setAppCheckProviderFactory(providerFactory)
//      
    FirebaseApp.configure()
      
//      if let appCheck = AppCheck.appCheck() {
//          let providerFactory = AppCheckDebugProviderFactory()
//          appCheck.setAppCheckProviderFactory(providerFactory)
//      }


    return true
  }
}

@main
struct fullyhacksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            HarmonAIHomeView()
        }
    }
}
