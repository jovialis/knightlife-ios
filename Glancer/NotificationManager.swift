//
//  NotificationManager.swift
//  Glancer
//
//  Created by Dylan Hanson on 8/5/18.
//  Copyright © 2018 Dylan Hanson. All rights reserved.
//

import Foundation
import AddictiveLib
import UserNotifications

class KLNotification {

	let id: String
	let date: Date
	
	init(date: Date) {
		self.id = UUID().uuidString
		self.date = date
	}
	
	init(id: String, date: Date) {
		self.id = id
		self.date = date
	}

}

class NotificationManager: Manager, PushRefreshListener {
	
	let projection = 10 // Schedule 10 days into the future.
	let shallowProjection = 2
	
	var refreshListenerType: [PushRefreshType] = [.SCHEDULE, .NOTIFICATIONS]
	
	static let instance = NotificationManager()
	var hub: UNUserNotificationCenter { return UNUserNotificationCenter.current() }

	let dispatchQueue = DispatchQueue(label: "notification registry") // Ensure that tasks are performed sequentially
	var currentDispatchItem: DispatchWorkItem?
	
//	Data
	private(set) var scheduledNotifications: [KLNotification] = []
	
//	Downloaded Specials
	private(set) var specialSchedules: [DateSchedule]?
	private(set) var specialSchedulesError: Error?
	var specialSchedulesLoaded: Bool {
		return self.specialSchedules != nil || self.specialSchedulesError != nil
	}
	
//	Downloaded template
	private(set) var template: [DayOfWeek: DaySchedule]?
	private(set) var templateError: Error?
	var templateLoaded: Bool {
		return self.template != nil || self.templateError != nil
	}
	
	init() {
		super.init("Notification")
		
		self.registerListeners()
		self.fetchSpecialSchedules()
		
		self.registerStorage(NotificationStorage(manager: self))
		self.cleanExpired()
	}
	
	private func registerListeners() {
		ScheduleManager.instance.templateWatcher.onSuccess(self) {
			self.template = $0
			self.templateError = nil
			
			self.scheduleNotifications(daysAhead: self.projection)
		}
		
		ScheduleManager.instance.templateWatcher.onFailure(self) {
			self.templateError = $0
			self.template = nil
		}
		
		ScheduleManager.instance.scheduleVariationUpdatedWatcher.onSuccess(self) {
			tuple in
			self.scheduleNotifications(daysAhead: 2) // Only schedule for 1 day ahead when settings are changed. This means if the user changes a lot at once, the system won't get too bogged down.
		}
	}
	
	func loadedNotifications(notification: KLNotification) {
		self.scheduledNotifications.append(notification)
	}
	
//	This is decently unnecessary, but I'm going to keep it here in case we ever fine tune this Manager in the future so it isn't so intensive.
	func cleanExpired() {
		let now = Date.today
		self.scheduledNotifications.removeAll(where: { $0.date < now })
	}
	
	func unregisterAll() {
		self.out("Unregistering all notifications.")
		let ids = self.scheduledNotifications.map({ $0.id })
		
		self.hub.removePendingNotificationRequests(withIdentifiers: ids)
		
		self.scheduledNotifications.removeAll()
		self.saveStorage()
	}
	
	func saveNotification(notification: KLNotification, save: Bool = true) {
//		self.out("Saving notification at time: \(notification.date.webSafeDate) \(notification.date.webSafeTime.replacingOccurrences(of: "-", with: ":"))")
		
		self.scheduledNotifications.append(notification)
		
		if save {
			self.saveStorage()
		}
	}
	
	func scheduleShallowNotifications() {
		self.scheduleNotifications(daysAhead: self.shallowProjection)
	}
	
	private func scheduleNotifications(daysAhead: Int) {
		if !self.templateLoaded {
			self.out("Couldn't schedule notifications: template not downloaded")
			return
		}
		
		guard let template = self.template else {
			self.out("Couldn't schedule notifications: no template present")
			return
		}
		
		if !self.specialSchedulesLoaded {
			self.out("Couldn't schedule notifications: Special Schedules not downloaded.")
			return
		}
		
		guard let specialSchedules = self.specialSchedules else {
			self.fetchSpecialSchedules()
			
			self.out("Couldn't schedule notifications: no special schedules present")
			return
		}
		
//		Cancel other active tasks. Schedule our own DispatchItem to handle the scheduling of the notifications.
		if let otherActiveDispatchItem = self.currentDispatchItem {
			otherActiveDispatchItem.cancel()
			self.currentDispatchItem = nil
		}

		var dispatchItem: DispatchWorkItem!
		dispatchItem = DispatchWorkItem() {
			let selfItem = dispatchItem!
		
			self.unregisterAll() // unregister all previous notifications.
//			self.out("----------------------------------------------------")
			
			let today = Date.today
			
			for i in 0..<daysAhead {
				if selfItem.isCancelled {
					break
				}
				
				let offsetDate = today.dayInRelation(offset: i)
				
				var schedule: DateSchedule!
				
				//				If there's a special schedule
				if let specialSchedule = specialSchedules.filter({ $0.date.webSafeDate == offsetDate.webSafeDate }).first {
					schedule = specialSchedule
				} else if let templateSchedule = template[offsetDate.weekday] {
					let dateSchedule = DateSchedule(date: offsetDate, day: nil, changed: false, notices: [], blocks: templateSchedule.getBlocks())
					schedule = dateSchedule
				} else {
					self.out("Couldn't find a suitable schedule for date: \(offsetDate.webSafeDate)")
					continue
				}
				
				for block in schedule.getBlocks() {
					if selfItem.isCancelled {
						break
					}

					let analyst = BlockAnalyst(schedule: schedule, block: block)
					
					if let course = analyst.getCourse() {
						if !course.showNotifications {
							continue // Skip!
						}
					} else if let meta = BlockMetaManager.instance.getBlockMeta(id: block.id) {
						if !meta.notifications {
							continue // Skip!
						}
					}
					
					guard let time = Date.mergeDateAndTime(date: offsetDate, time: block.time.start) else {
						self.out("Failed to find start time for block: \(block)")
						continue
					}
					
					guard let adjustedTime = Calendar.normalizedCalendar.date(byAdding: .minute, value: -5, to: time) else {
						self.out("Failed to find adjusted start time for block: \(block)")
						continue
					}
					
					let klnotification = KLNotification(date: adjustedTime)
					
					let content = self.buildNotificationContent(block: block, schedule: schedule)
					let components = Calendar.normalizedCalendar.dateComponents([.year, .month, .day, .hour, .minute, .calendar, .timeZone], from: adjustedTime)
					let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
					
					let request = UNNotificationRequest(identifier: klnotification.id, content: content, trigger: trigger)
					
					if selfItem.isCancelled {
						return
					}
					
					self.hub.add(request) {
						error in
						
						if error != nil {
							self.out("Failed to add notification: \(error!.localizedDescription)")
						} else {
							if selfItem.isCancelled { // If the item is cancelled by the time the hub registers this, we have no real choice but to remove it immediately. I doubt this will hurt the hub at all but don't quote me on that.
								self.hub.removePendingNotificationRequests(withIdentifiers: [klnotification.id])
								return
							}
							
							self.saveNotification(notification: klnotification)
						}
					}
				}
			}
		}
		
		self.currentDispatchItem = dispatchItem
		self.dispatchQueue.async(execute: dispatchItem)
	}
	
	private func buildNotificationContent(block: Block, schedule: DateSchedule) -> UNNotificationContent {
		let analyst = BlockAnalyst(schedule: schedule, block: block)
		
		let content = UNMutableNotificationContent()
		if analyst.getCourse() == nil {
			content.title = "Next Block"
		} else {
			content.title = "Get to Class"
		}
		
		content.body = "\(analyst.getDisplayName()) in 5 min."
		
		
		content.title = "Get to Class"
		content.body = "5 min until \(analyst.getDisplayName())"
		
		if analyst.getLocation() != nil {
			content.body = content.body + " \(analyst.getLocation()!)"
		}
		
		return content
	}
	
	func doListenerRefresh(date: Date) {
		self.fetchSpecialSchedules()
	}
	
	func fetchSpecialSchedules() {
		self.specialSchedules = nil
		self.specialSchedulesError = nil
		
		SpecialSchedulesWebCall(date: Date.today).callback() {
			result in
			
			switch result {
			case .success(let payload):
				self.specialSchedules = payload
				self.specialSchedulesError = nil
			case .failure(let error):
				self.specialSchedules = nil
				self.specialSchedulesError = error
			}
			
			self.finishedSpecialSchedulesFetch()
		}.execute()
	}
	
	func finishedSpecialSchedulesFetch() {
		self.scheduleNotifications(daysAhead: self.projection)
	}
	
}
