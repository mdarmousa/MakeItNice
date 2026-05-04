//
//  MakeItNiceApp.swift
//  MakeItNice
//
//  Created by Mohammad Darmousa on 05/05/2026.
//

import SwiftUI

@main
struct MakeItNiceApp: App {
    var body: some Scene {
        MenuBarExtra("Make It Nice", systemImage: "bolt.fill") {
            RewriteView()
                .frame(minWidth: 360, minHeight: 460)
        }
        .menuBarExtraStyle(.window)
    }
}
