import func SwiftUI.__designTimeFloat
import func SwiftUI.__designTimeString
import func SwiftUI.__designTimeInteger
import func SwiftUI.__designTimeBoolean

#sourceLocation(file: "/Users/gavin_wu/Desktop/Genesyslogic/2025/ZoneTruthHost/ZoneTruthHost/ContentView.swift", line: 1)
//
//  ContentView.swift
//  ZoneTruthHost
//
//  Created by Gavin_Wu on 2026/5/20.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: __designTimeString("#5563_0", fallback: "globe"))
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(__designTimeString("#5563_1", fallback: "Hello, world!"))
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
