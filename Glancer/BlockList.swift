//
//  BlockList.swift
//  Glancer
//
//  Created by Dylan Hanson on 11/3/17.
//  Copyright © 2017 BB&N. All rights reserved.
//

import Foundation

struct BlockList
{
	let blocks: [ScheduleBlock]
}

extension BlockList: Equatable
{
	static func ==(lhs: BlockList, rhs: BlockList) -> Bool
	{
		if lhs.blocks.count != rhs.blocks.count
		{
			return false
		}
		
		for i in 0..<lhs.blocks.count
		{
			if lhs.blocks[i] != rhs.blocks[i]
			{
				return false
			}
		}
		
		return true
	}
	
	var hashValue: Int
	{
		var val = 123
		for block in self.blocks
		{
			val ^= block.hashValue
		}
		return val
	}
}