//
//  TableViewController.m
//  STRyper
//
//  Created by Jean Peccoud on 13/02/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.



#import "TableViewController.h"
#import "GaugeTableCellView.h"
#import "Chromatogram.h"
#import "MainWindowController.h"
#import "FileImporter.h"
#import "IndexImageView.h"
#import "TableSortPopover.h"

TableSortPopover *tableSortPopover;



ColumnDescriptorKey KeyPathToBind = @"keyPathToBind",
CellViewID =  @"cellViewID",
ColumnTitle = @"columnTitle",
IsTextFieldEditable = @"isTextFieldEditable",
IsColumnVisibleByDefault = @"columnVisibleByDefault";

@implementation TableViewController


#pragma mark - methods for populating the table and common delegate methods

+ (instancetype)sharedController {
	static TableViewController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (NSArrayController *)tableContent {
	if(!_tableContent) {		/// tableContent is an outlet, which may be nil if the nib is not loaded yet, so we access our view property to load it
		if(self.view) {
			return _tableContent;
		}
	}
	return _tableContent;
}

- (NSTableView *)viewForCellPrototypes {
	if(!_viewForCellPrototypes) {
		return self.tableView;
	}
	return _viewForCellPrototypes;
}


- (NSString *)nameForItem:(id)item {
	return (@"Item");
}


- (NSString *)entityName {
	return CodingObject.entity.name;
}


- (BOOL)shouldAutoSaveTable {
	return YES;
}


- (void)viewDidLoad {
	
	[super viewDidLoad];
	[self configureTableContent];

	self.tableView.delegate = self;
	self.tableView.dataSource = self;
	[self addColumnsToTable];
	
	if([self shouldAutoSaveTable]) {
		/// we set the autosave name our tableview now, as it can only work after the columns are added
		self.tableView.autosaveName = [self.tableView.identifier stringByAppendingString:@"_tableViewSave"];
		self.tableView.autosaveTableColumns = YES;
	}
	
	if([self shouldMakeTableHeaderMenu]) {
		NSMenu *menu = NSMenu.new;
		self.tableView.headerView.menu = menu;
		menu.delegate = (id) self;
	}
}


- (void)configureTableContent {
	if(self.tableContent) {			/// these are the default bindings common to most subclasses (the usual bindings to NSTableView)
		[self.tableContent bind:NSManagedObjectContextBinding toObject:NSApp.delegate
					withKeyPath:NSStringFromSelector(@selector(managedObjectContext)) options:@{NSDeletesObjectsOnRemoveBindingsOption: @([self shouldDeleteObjectsOnRemove])}];
		self.tableContent.entityName = self.entityName;
		[self.tableView bind:NSContentBinding toObject:self.tableContent withKeyPath:NSStringFromSelector(@selector(arrangedObjects)) options:nil];
		[self.tableView bind:NSSelectionIndexesBinding toObject:self.tableContent
				 withKeyPath:NSStringFromSelector(@selector(selectionIndexes)) options:nil];
		[self.tableView bind:NSSortDescriptorsBinding toObject:self.tableContent
				 withKeyPath:NSStringFromSelector(@selector(sortDescriptors)) options:nil];
	}
}


- (nullable NSDictionary *)columnDescription {
	return nil;
}


- (nullable NSArray<NSString *> *)orderedColumnIDs {
	return nil;
}


- (void)addColumnsToTable {
	if(!self.orderedColumnIDs) {
		return;
	}
	for (NSString *ID in self.orderedColumnIDs) {
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:ID];
		col.title = self.columnDescription[ID][ColumnTitle];
		col.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:self.columnDescription[ID][KeyPathToBind] ascending:YES];
		[self.tableView addTableColumn:col];
		
		col.width = col.headerCell.cellSize.width + 10;
		col.minWidth = col.headerCell.cellSize.width ;
		col.hidden = ![self.columnDescription[ID][IsColumnVisibleByDefault] boolValue];
		
	}
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *ID = tableColumn.identifier;
	if(!ID) {
		return nil;
	}
	
	NSTableCellView *view = [tableView makeViewWithIdentifier:ID owner:self];
	if(view) {
		return view;		/// which should be the view set in interface builder, if it exists (by default it has the same identifier as the column)
	}
	
	NSDictionary *columnDescription = self.columnDescription;
	if(!columnDescription) {
		return nil;
	}
	
	NSString *viewID = columnDescription[ID][CellViewID];  /// in no such view exists, we return the right prototype table cell view that is in the sampleTable (in the xib)
	view = [self.viewForCellPrototypes makeViewWithIdentifier:viewID owner:self];
	if(!view) {
		return  nil;					/// hopefully, this won't happen otherwise some views will be missing
	}
	
	if(view.subviews.count == 0) {
		return nil;
	}
	
	/// we bind elements in this cell to properties of the object is represents.
	/// We could have done it in IB, but it is clearer to do it in code. The bindings are also described in +columnDescription
	NSString *keyPath;
	view.identifier = ID;
	NSTextField *textField = view.textField;
	if(textField) {
		keyPath = [@"objectValue." stringByAppendingString: columnDescription[ID][KeyPathToBind]];
		[textField bind:NSValueBinding toObject:view withKeyPath:keyPath options:@{NSValidatesImmediatelyBindingOption:@YES}];
		textField.selectable = YES;
		textField.editable = [columnDescription[ID][IsTextFieldEditable] boolValue];
	}
	
	if(view.imageView) {
		if([view.imageView respondsToSelector:@selector(imageIndex)]) {
			keyPath = [@"objectValue." stringByAppendingString: columnDescription[ID][ImageIndexBinding]];
			[view.imageView bind:ImageIndexBinding toObject:view withKeyPath:keyPath options:nil];
		}
		if (!view.textField) {		/// the cells only showing an image (no textfield), we bind to the tooltip
			keyPath = [@"objectValue." stringByAppendingString: columnDescription[ID][KeyPathToBind]];
			[view.imageView bind:NSToolTipBinding toObject:view withKeyPath:keyPath options:nil];
		}
	}
	
	if([view isKindOfClass: GaugeTableCellView.class]) {
		keyPath = [@"objectValue." stringByAppendingString: columnDescription[ID][KeyPathToBind]];
		[view bind:NSValueBinding toObject:view withKeyPath:keyPath options:nil];
	}
	
	return view;
	
}

#pragma mark - column visibility and width

- (BOOL)shouldMakeTableHeaderMenu {
	return NO;
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	if(menu == self.tableView.headerView.menu) {		/// we populate the menu with items representing the columns that the user can show/hide.
		[menu removeAllItems];							/// we do it every time the menu appears so that the columns are in the order of the table (the user may have reordered columns)
		/// we first add the item allowing to sort the table. We don't need to recreate this item each time, but this isn't costly.
		if([self canSortByMultipleColumns]) {
			/// There must be at least two visible columns
			NSArray *visibleColumns = [self.tableView.tableColumns filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"hidden == NO"]];
			if(visibleColumns.count >= 2) {
				NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Sort Table…" action:@selector(showSortCriteria:) keyEquivalent:@""];
				item.target = self;
				[menu addItem:item];
			}
		}
		
		/// we add a menu item allowing to hide the clicked column. To identify this column, we use the mouse location
		NSPoint clickPoint = [self.tableView.headerView convertPoint:NSApp.currentEvent.locationInWindow fromView:nil];
		NSInteger clickedCol = [self.tableView.headerView columnAtPoint:clickPoint];
		if(clickedCol >= 0) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Hide Column" action:@selector(hideColumn:) keyEquivalent:@""];
			item.target = self;
			item.representedObject = self.tableView.tableColumns[clickedCol];
			[menu addItem:item];
		}
		
		if(menu.itemArray.count > 0) {
			[menu addItem:NSMenuItem.separatorItem];
		}

		for(NSTableColumn *col in self.tableView.tableColumns) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:col.title action:@selector(toggleColumnVisibility:) keyEquivalent:@""];
			item.target = self;
			item.representedObject = col;
			item.state = !col.hidden;
			[menu addItem:item];
		}
		return;
	}
	
	if(menu == self.tableView.menu) {		/// if the menu is from our tableview's menu (set in IB), we hide its items if there is no clicked row
		for(NSMenuItem *menuItem in menu.itemArray) {
			menuItem.hidden = self.tableView.clickedRow < 0;
		}
	}
}


- (void)hideColumn:(NSMenuItem *)sender {
	NSTableColumn *column = sender.representedObject;
	if(column) {
		column.hidden = YES;
	}
}

- (void)toggleColumnVisibility:(NSMenuItem *)sender {
	NSTableColumn *column = sender.representedObject;
	if(column) {
		column.hidden = !column.hidden;
	}
}


- (CGFloat)tableView:(NSTableView *)tableView sizeToFitWidthOfColumn:(NSInteger)column {
	NSTableColumn *theColumn = tableView.tableColumns[column];
	NSSize textSize = theColumn.headerCell.cellSize; 									/// the column should be at least as large as the header text
	CGFloat maxWidth = textSize.width +5;
	
	for (int row = 0; row < tableView.numberOfRows; row++) {
		NSTableCellView *cellView = [tableView viewAtColumn:column row:row makeIfNecessary:NO];
		if(cellView.textField) {
			textSize = cellView.textField.cell.cellSize; 								/// do not use view.fittingSize here. It isn't reliable.
			textSize.width = textSize.width + NSMinX(cellView.textField.frame) +2;   	/// not sure why, but if we don't do that it clips the contents
		} else {
			NSPopUpButton *button = [cellView viewWithTag:1];
			if(button) {
				textSize = button.cell.cellSize;
			}
		}
		 
		if (textSize.width > maxWidth) {
			maxWidth = textSize.width;
		}
	}
	return maxWidth;
}

#pragma mark - pasteboard support


- (NSString *)stringForObject:(id) object {
	NSString *string = @"";
	NSArray *tableColumns = [self.tableView.tableColumns filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSTableColumn *column, NSDictionary<NSString *,id> * _Nullable bindings) {
		return !column.hidden;
	}]];
	NSTableColumn *lastColumn = tableColumns.lastObject;
	for (NSTableColumn *column in tableColumns) {
		string = [string stringByAppendingString: [self stringCorrespondingToColumn:column forObject:object]];
		if(column != lastColumn) {
			string = [string stringByAppendingString: @"\t"];
		}
	}
	
	return string;
}



- (NSString *)stringCorrespondingToColumn:(NSTableColumn *)column forObject:(id) object {
	NSString *string = @"";
	NSDictionary *columnDescription = self.columnDescription[column.identifier];
	NSString *keyPath = columnDescription[KeyPathToBind];
	if(keyPath) {
		id value = [object valueForKeyPath:keyPath];
		if(!value) {
			return string;
		}
		if([value isKindOfClass:NSDate.class]) {		/// we format dates as in the table
														/// we could also format numbers, but raw values are more precise
			NSString *identifier = columnDescription[CellViewID];
			if(identifier) {
				NSTableCellView *cellView = [self.tableView makeViewWithIdentifier:identifier owner:self];
				NSDateFormatter *formatter = cellView.textField.cell.formatter;
				if(formatter) {
					string = [formatter stringFromDate:value];
					if(string) {
						return string;
					}
				}
			}
		}
		string = [NSString stringWithFormat:@("%@"), value];
	}
	return string;
}


- (IBAction)copy:sender {
	/// we copy a string representing selected objects, we can be pasted to text editors or spreadsheets
	NSArray *items = [self targetItemsOfSender:sender];
	[self copyItems:(NSArray *) items ToPasteBoard:NSPasteboard.generalPasteboard];
}


-(void) copyItems:(NSArray *) items ToPasteBoard:(NSPasteboard *)pasteboard {
	if(items.count > 0) {
		/// We make a string that represents the visible content of the selected rows (one line per row)
		NSMutableArray *pasteboardStrings = [NSMutableArray arrayWithCapacity:items.count];
		for(id object in items) {
			NSString *string = [self stringForObject:object];
			if(string) {
				[pasteboardStrings addObject:string];
			}
		}
		NSString *pasteboardString = [pasteboardStrings componentsJoinedByString:@"\n"];
		
		[pasteboard clearContents];
		NSPasteboardItem *item = NSPasteboardItem.new;
		[item setString:pasteboardString forType:NSPasteboardTypeString];
		[pasteboard writeObjects:@[item]];
		
		/// We also write a combined string containing the object IDs of selected elements, if we support it.
		/// Using a single pasteboard item is much faster than using one per copied element, when we paste.
		NSPasteboardType pasteboardType = self.pasteboardTypeForCombinedItems;
		if(pasteboardType) {
			[self.tableContent.managedObjectContext obtainPermanentIDsForObjects:items error:nil];
			NSArray *URIStrings = [items valueForKeyPath:@"@unionOfObjects.objectID.URIRepresentation.absoluteString"];
			NSString *concat = [URIStrings componentsJoinedByString:@"\n"];
			[item setString:concat forType:pasteboardType];
		} else {
			/// if we don't support this, we copy each item to the pasteboard
			if([items.firstObject conformsToProtocol:@protocol(NSPasteboardWriting)]) {
				[pasteboard writeObjects:items];
			}
		}
	}
}


- (NSPasteboardType)pasteboardTypeForCombinedItems {
	return nil;
}

# pragma mark - renaming, adding and removing items

- (IBAction)rename:(id)sender {
	NSInteger row = -1;
	if([sender respondsToSelector:@selector(topMenu)]) {
		NSMenu *menu = [sender topMenu];
		if(menu == self.tableView.menu) {
			row = self.tableView.clickedRow;
		} else {
			row = self.tableView.selectedRow;
		}
	} else {
		row = self.tableView.selectedRow;
	}
	if(row >= 0) {
		[self.tableView editColumn:self.itemNameColumn row:row withEvent:nil select:YES];
	}
}


- (BOOL)canRenameItem:(id)item {
	return item != nil;
}


- (void)selectItemName:(id)object {
	NSInteger row = [self.tableContent.arrangedObjects indexOfObject: object];
	if(row >=0) {
		[self.tableView editColumn:[self itemNameColumn] row:row withEvent:nil select:YES];
	}
}


- (NSInteger)itemNameColumn {
	return 0;
}


- (nullable NSArray *) targetItemsOfSender:(id)sender {
	if(!self.tableContent) {
		return nil;
	}
	if([sender respondsToSelector:@selector(topMenu)]) {
		NSInteger clickedRow = self.tableView.clickedRow;
		if([sender topMenu] == self.tableView.menu && clickedRow >= 0) {
			/// the target may be at the clicked row, which can differ from the selected row(s)
			NSArray *arrangedObjects = self.tableContent.arrangedObjects;
			if(arrangedObjects.count >= clickedRow) {
				id clickedItem = arrangedObjects[clickedRow];
				if([self.tableContent.selectedObjects containsObject:clickedItem]) {
					return self.tableContent.selectedObjects;
				}
				return @[clickedItem];
			}
		}
	}
	return self.tableContent.selectedObjects;
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	/// The implementation assumes menuItem belongs either to the tableview's menu (if there is one) or the main application's menu.

	if(menuItem.action == @selector(remove:)) {
		/// we give a contextual title to the menu that removes an item.
		NSString *title = [self removeActionTitleForItems:[self targetItemsOfSender:menuItem]];
		if(title) {
			menuItem.title = title;
			menuItem.hidden = NO;
			return YES;
		}
		menuItem.title = @"Remove";
		menuItem.hidden = YES;
		/// absence of title means there is nothing to remove, so we disable the menu item
		/// (which in this case should be from the main application menu, as we hide all items from the contextual menu if there is no clicked item)
		return NO;
	}
	
	if(menuItem.action == @selector(rename:) && menuItem.topMenu == NSApp.menu) {
		/// we give a contextual title to the menu that renames an item.
		id item = [self targetItemsOfSender:menuItem].firstObject;
		if([self canRenameItem:item]) {
			menuItem.title = [@"Rename " stringByAppendingString: [self nameForItem:[self targetItemsOfSender:menuItem].firstObject]];
			return YES;
		}
		return NO;
	}
	
	if(menuItem.action == @selector(showSortCriteria:)) {
		return [self canSortByMultipleColumns];
	}
	
	if(menuItem.action == @selector(moveSelectionByStep:)) {
		return self.tableContent.selectedObjects.count > 0;
	}
	
	if(menuItem.action == @selector(copy:)) {
		if(menuItem.topMenu == self.tableView.menu) {
			return self.tableView.clickedRow >= 0;
		}
		return self.columnDescription && self.tableContent.selectedObjects.count > 0;
	}

	return YES;
}


- (IBAction)remove:(id)sender {
	if(FileImporter.sharedFileImporter.importOnGoing) {
		return;
	}
	NSArray *items = [self targetItemsOfSender:sender];
	if(items.count == 0) {
		return;
	}
	NSAlert *alert;
	alert = [self cannotRemoveAlertForItems:items];
	if(alert) {
		[alert beginSheetModalForWindow: self.view.window completionHandler:^(NSModalResponse returnCode) {
		}];
		return;
	}
	
	NSString *actionName = [self removeActionTitleForItems:items];
	alert = [self cautionAlertForRemovingItems:items];
	if(alert) {
		[alert beginSheetModalForWindow: self.view.window completionHandler:^(NSModalResponse returnCode) {
			if(returnCode == NSAlertFirstButtonReturn) {
				///	[self removeSelectedObjects:objects];  // before we remove the objects, we remove them from the selection. This is because the detailed view shows selected samples, which are somehow not removed from the selection after being deleted (although they get removed from the selection at some point).
				[self removeItems:items];
				[self.undoManager setActionName:actionName];
			}
		}];
		return;
	}
	[self removeItems:items];
	[self.undoManager setActionName:actionName];
	
}


- (nullable NSString *)removeActionTitleForItems:(NSArray *)items {
	if(items.count == 0) {
		return nil;
	}
	NSString *actionName = [@"Delete " stringByAppendingString: [self nameForItem:items.firstObject]];
	if(items.count > 1) {
		actionName = [actionName stringByAppendingString:@"s"];
	}
	return actionName;
}


- (void)removeItems:(NSArray *)items {

	if(self.tableContent) {
		/// here, we assume that the tableContent controller has the "delete object on remove" active if its content is bound to a relationship
		[self.tableContent removeObjects:items];
	} else {
		for(NSManagedObject *item in items) {
			[item.managedObjectContext deleteObject:item];
		}
	}
	[(AppDelegate *)NSApp.delegate saveAction:self];
}



- (nullable NSAlert *)cautionAlertForRemovingItems:(NSArray *)items {
	NSString *actionName = [self removeActionTitleForItems:items];
	
	NSAlert *alert = NSAlert.new;
	alert.messageText =  [actionName stringByAppendingString:@"?"];
	[alert addButtonWithTitle:actionName];
	[alert addButtonWithTitle:@"Cancel"];
	NSString *informativeText = [self cautionAlertInformativeStringForItems:items];
	if(informativeText) {
		alert.informativeText = informativeText;
	}
	return alert;
	
}


- (nullable NSAlert *)cannotRemoveAlertForItems:(NSArray *)items {
	if([self canAlwaysRemove]) {
		return nil;
	}
	NSAlert *alert = NSAlert.new;
	NSString *itemNames = [self nameForItem:items.firstObject].lowercaseString;
	if(items.count > 1) {
		itemNames = [itemNames stringByAppendingString:@"s"];
	}
	alert.messageText = [NSString stringWithFormat: @"The %@ cannot be removed.", itemNames];
	NSString *informativeText = [self cannotRemoveInformativeStringForItems:items];
	if(informativeText) {
		alert.informativeText = informativeText;
	}
	[alert addButtonWithTitle:@"OK"];
	return alert;
	
}


- (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	return @"This action can be undone.";
}


- (nullable NSString *)cannotRemoveInformativeStringForItems:(NSArray *)items {
	return nil;
}


- (BOOL)canAlwaysRemove {
	return YES;
}

- (BOOL)shouldDeleteObjectsOnRemove {
	return YES;
}


- (BOOL)canSortByMultipleColumns {
	return self.shouldMakeTableHeaderMenu;
}


#pragma mark - table sorting

static NSString *const AscendingOrderKey = @"AscendingOrderKey";
static NSString *const KeypathKey = @"KeypathKey";

/// shows the popover allowing to sort the table according to (visible) columns
- (IBAction)showSortCriteria:(id)sender {
	if(!self.columnDescription) {
		return;
	}
	
	/// The sort criteria we propose correspond to visible columns
	NSArray *visibleColumns = [self.tableView.tableColumns filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSTableColumn *column, NSDictionary<NSString *,id> * _Nullable bindings) {
		return !column.hidden;
	}]];
	
	if(visibleColumns.count < 1) {
		return;
	}
	
	/// We prepare the sort criteria editor
	NSArray *columnTitles = [visibleColumns valueForKeyPath:@"@unionOfObjects.title"];
	NSMutableArray *keypaths = [NSMutableArray arrayWithCapacity:visibleColumns.count];
	for(NSTableColumn *column in visibleColumns) {
		NSString *keypath = self.columnDescription[column.identifier][KeyPathToBind];
		if(keypath) {
			[keypaths addObject:keypath];
		} else {
			NSLog(@"Missing keypath for column identifier '%@'.", column.identifier);
			return;
		}
	}
	
	/// We show the sort criteria that were last applied
	NSArray *lastSortCriteria = [NSUserDefaults.standardUserDefaults arrayForKey:[self.tableView.identifier stringByAppendingString:@"_sortCriteria"]];
	
	NSMutableArray *sortDescriptors = [NSMutableArray arrayWithCapacity:lastSortCriteria.count];
	
	for(NSDictionary *dic in lastSortCriteria) {
		if([dic isKindOfClass:NSDictionary.class]) {
			NSString *keypath = dic[KeypathKey];
			if(keypath && [keypaths containsObject: keypath]) {
				[sortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:keypath ascending:dic[AscendingOrderKey]]];
			} else {
				[sortDescriptors removeAllObjects];
				break;
			}
		}
	}
	
	if(sortDescriptors.count < 1) {
		/// If we could not retrieved sort descriptors, we show a default one based on the first visible column
		NSString *keypath = self.columnDescription[[visibleColumns.firstObject identifier]][KeyPathToBind];
		if(keypath) {
			sortDescriptors = [NSMutableArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:keypath ascending:YES]];
		} else {
			NSLog(@"Unable to generate sort descriptors.");
			return;
		}
	}
	
	if(!tableSortPopover) {
		tableSortPopover = TableSortPopover.new;
		tableSortPopover.behavior = NSPopoverBehaviorTransient;
	}
	
	[tableSortPopover.sortCriteriaEditor setTitles:columnTitles forKeyPath:keypaths];
	tableSortPopover.sortCriteriaEditor.sortDescriptors = sortDescriptors;
	
	tableSortPopover.sortAction = @selector(applySort:);
	tableSortPopover.sortActionTarget = self;
	NSTableHeaderView *headerView = self.tableView.headerView;
	[tableSortPopover showRelativeToRect:headerView.bounds ofView:headerView preferredEdge:NSMaxYEdge];
}


- (void)applySort:(id)sender {
	NSArray *sortDescriptors = tableSortPopover.sortCriteriaEditor.sortDescriptors;
	if([sortDescriptors isEqualToArray:self.tableView.sortDescriptors]) {
		[self.tableContent rearrangeObjects];
	} else {
		self.tableView.sortDescriptors = sortDescriptors;
	}
	[tableSortPopover close];
	
	/// we save the specified sort descriptors to the user defaults
	NSMutableArray *sortDictionaries = [NSMutableArray arrayWithCapacity:sortDescriptors.count];
	for(NSSortDescriptor *sortDescriptor in sortDescriptors) {
		NSDictionary *sortCriterion =  @{KeypathKey: sortDescriptor.key,
										 AscendingOrderKey: @(sortDescriptor.ascending)};
		[sortDictionaries addObject:sortCriterion];
	}
	
	[NSUserDefaults.standardUserDefaults setObject:sortDictionaries forKey:[self.tableView.identifier stringByAppendingString:@"_sortCriteria"]];

}


#pragma mark - other


- (void)tableViewIsClicked:(NSTableView *)sender {	/// when our tableview is clicked, we set ourselves as source for the content of the detailed outline view
	MainWindowController.sharedController.sourceController = self;
}


- (void)moveSelectionByStep:(id)sender {
	NSIndexSet *selectedRows = self.tableView.selectedRowIndexes;
	if (selectedRows.count < 1) {
		return;
	}
	int increment = 1;
	if([[sender identifier] isEqualToString:@"moveUp"]) {
		increment = -increment;
	}
	NSMutableIndexSet *newSelectedRows = NSMutableIndexSet.new;
	[selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		long row = idx + increment;
		if(row < 0 | row >= self.tableView.numberOfRows-1) {
			*stop = YES;
		}
		[newSelectedRows addIndex:row];
	}];
	if (newSelectedRows.count == selectedRows.count) {
		[self.tableView selectRowIndexes:newSelectedRows byExtendingSelection:NO];
		if(increment > 0) {
			[self.tableView scrollRowToVisible:newSelectedRows.lastIndex];
		} else {
			[self.tableView scrollRowToVisible:newSelectedRows.firstIndex];
		}

	}
	
}


@end



