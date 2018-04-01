//
//  EventManager.swift
//  Glancer
//
//  Created by Dylan Hanson on 12/15/17.
//  Copyright © 2017 Dylan Hanson. All rights reserved.
//

import Foundation

class EventManager: Manager
{
	static let instance = EventManager()

	private(set) var eventHandler: GetEventsResourceHandler!
	
	init()
	{
		super.init(name: "Event Manager")
		
		self.eventHandler = GetEventsResourceHandler(self)
	}
}