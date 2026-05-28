//
//  metabolic_easy_chatApp.swift
//  metabolic_easy_chat
//
//  Created by 向滢澔 on 2026/5/19.
//

import SwiftUI

@main
struct metabolic_easy_chatApp: App {
    @StateObject private var appUpdateController = AppUpdateController()

    var body: some Scene {
        WindowGroup("EasyChat-新陈代谢") {
            ContentView()
                .environment(\.appUpdateController, appUpdateController)
        }
    }
}
