//
//  Array+ChatPosition.swift
//  BetterTG
//
//  Created by Lev Poznyakov on 27.08.2023.
//

import TDLibKit

extension [ChatPosition] {
    var main: ChatPosition {
        first(where: { $0.list == .chatListMain })!
        // ?? .init(isPinned: false, list: .chatListMain, order: 0, source: nil)
    }
}
