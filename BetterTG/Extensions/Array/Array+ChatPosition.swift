//
//  Array+ChatPosition.swift
//  BetterTG
//
//  Created by Lev Poznyakov on 27.08.2023.
//

import TDLibKit

extension [ChatPosition] {
    func first(_ chatList: ChatList) -> ChatPosition? {
        first(where: { $0.list == chatList })
    }
}
