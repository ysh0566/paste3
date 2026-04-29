//
//  Item.swift
//  paste3
//
//  Created by 余生辉 on 2026/4/29.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
