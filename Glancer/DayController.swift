//
//  DayController.swift
//  Glancer
//
//  Created by Dylan Hanson on 7/25/18.
//  Copyright © 2018 Dylan Hanson. All rights reserved.
//

import Foundation
import UIKit
import AddictiveLib

class DayController: UIViewController, TableBuilder, ErrorReloadable {

	@IBOutlet weak var tableView: UITableView!
	var tableHandler: TableHandler!
	
	var date: Date!
	
	var bundle: DayBundle?
	var bundleError: Error?
	var bundleDownloaded: Bool { return bundle != nil || bundleError != nil }
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		self.tableHandler = TableHandler(table: self.tableView)
		self.tableHandler.builder = self
		
		self.tableView.delaysContentTouches = false
		
		self.registerListeners()
		self.reloadData()
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		self.registerListeners()
		
		self.tableHandler.reload()
		self.setupNavigationItem()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		//		TODO: UNREGISTER ON UNWIND.
		self.unregisterListeners()
	}
	
	func reloadData() {
		self.bundle = nil
		self.bundleError = nil
		
		self.tableHandler.reload()
		
		DayBundleManager.instance.getDayBundle(date: self.date)
	}
	
	func registerListeners() {
		DayBundleManager.instance.getBundleWatcher(date: self.date).onSuccess(self) {
			bundle in
			
			self.bundle = bundle
			self.bundleError = nil
			
			self.tableHandler.reload()
		}
		
		DayBundleManager.instance.getBundleWatcher(date: self.date).onFailure(self) {
			error in
			
			self.bundle = nil
			self.bundleError = error
			
			self.tableHandler.reload()
		}
		
		ScheduleManager.instance.getVariationWatcher(day: self.date.weekday).onSuccess(self) {
			variation in
			self.tableHandler.reload()
		}
	}
	
	func unregisterListeners() {
		DayBundleManager.instance.getBundleWatcher(date: self.date).unregisterFailure(self)
		DayBundleManager.instance.getBundleWatcher(date: self.date).unregisterSuccess(self)
		
		ScheduleManager.instance.getVariationWatcher(day: self.date.weekday).unregisterSuccess(self)
	}
	
	func setupNavigationItem() {
		self.navigationItem.title = self.date.prettyDate
		
		if let subtitleItem = self.navigationItem as? SubtitleNavigationItem {
			if let bundle = self.bundle {
				if bundle.schedule.changed {
					subtitleItem.subtitle = "Special"
					subtitleItem.subtitleColor = .red
					
					return
				}
			}
			
			subtitleItem.subtitle = nil
			subtitleItem.subtitleColor = UIColor.darkGray
		}
	}
	
	func buildCells(layout: TableLayout) {
		self.setupNavigationItem()
		
		if !self.bundleDownloaded {
			self.showLoading(layout: layout)
			return
		}
		
		if let _ = self.bundleError {
			self.showError(layout: layout)
			return
		}
		
		if self.bundle!.schedule.getBlocks().isEmpty {
			self.showNone(layout: layout)
			return
		}
		
		let composites = self.generateCompositeList(bundle: self.bundle!, blocks: self.bundle!.schedule.getBlocks())
		self.tableHandler.addModule(BlockListModule(controller: self, composites: composites))		
	}
	
	func showNone(layout: TableLayout) {
		layout.addSection().addCell(NoClassCell()).setHeight(self.tableView.bounds.size.height)
	}
	
	func showLoading(layout: TableLayout) {
		layout.addSection().addCell(LoadingCell()).setHeight(self.tableView.bounds.size.height)
	}
	
	func showError(layout: TableLayout) {
		layout.addSection().addCell(ErrorCell(reloadable: self)).setHeight(self.tableView.bounds.size.height)
	}
	
	func generateCompositeList(bundle: DayBundle, blocks: [Block]) -> [CompositeBlock] {
		var list: [CompositeBlock] = []
		for block in blocks {
			list.append(self.generateCompositeBlock(bundle: bundle, block: block))
		}
		return list
	}
	
	func generateCompositeBlock(bundle: DayBundle, block: Block) -> CompositeBlock {
		return CompositeBlock(schedule: bundle.schedule, block: block, lunch: (block.id == .lunch && !bundle.menu.items.isEmpty ? bundle.menu : nil), events: bundle.events.getEventsByBlock(block: block.id))
	}
	
	func openLunchMenu(menu: LunchMenu) {
		guard let controller = self.storyboard?.instantiateViewController(withIdentifier: "Lunch") as? LunchController else {
			return
		}
		
		controller.menu = menu
		self.navigationController?.pushViewController(controller, animated: true)
	}
	
}
