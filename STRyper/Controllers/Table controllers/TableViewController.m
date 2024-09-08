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
#import "SampleSearchHelper.h"
#import "NSPredicate+PredicateAdditions.h"
#import "NSManagedObjectContext+NSManagedObjectContextAdditions.h"
@import QuartzCore;

ColumnDescriptorKey KeyPathToBind = @"keyPathToBind",
CellViewID =  @"cellViewID",
ColumnTitle = @"columnTitle",
IsTextFieldEditable = @"isTextFieldEditable",
IsColumnVisibleByDefault = @"columnVisibleByDefault",
IsColumnSortingCaseInsensitive = @"columnSortingCaseInsensitive";

@interface TableViewController ()

@property (nonatomic) NSImage *filterButtonImageActive;
@property (nonatomic) NSImage *filterButtonImageInactive;
@property (nonatomic) NSString *URIStringPrefix;
@property (nonatomic) CALayer *flashLayer;

@end


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
	
	NSTableView *tableView = self.tableView;
	tableView.delegate = self;
	tableView.dataSource = self;
	[self addColumnsToTable];
	
	if(self.shouldAutoSaveTable) {
		/// we set the autosave name our tableview now, as it can only work after the columns are added
		tableView.autosaveName = [tableView.identifier stringByAppendingString:@"_tableViewSave"];
		tableView.autosaveTableColumns = YES;
	}
	
	for(NSTableColumn *col in tableView.tableColumns) {
		if(![self canHideColumn:col]) {
			col.hidden = NO;
		}
	}
	
	if(self.shouldMakeTableHeaderMenu) {
		NSMenu *menu = NSMenu.new;
		tableView.headerView.menu = menu;
		menu.delegate = (id) self;
	}
	
	NSSplitView *view = (NSSplitView *)self.view;
	if([view isKindOfClass:NSSplitView.class]) {
		view.autosaveName = view.identifier;
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


- (NSDictionary<NSString *, id> *)columnDescription {
	return nil;
}


- (nullable NSArray<NSString *> *)orderedColumnIDs {
	return nil;
}


- (void)addColumnsToTable {
	if(!self.orderedColumnIDs) {
		return;
	}
	NSTableView *tableView = self.tableView;
	NSDictionary *columnDescription = self.columnDescription;
	for (NSString *ID in self.orderedColumnIDs) {
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:ID];
		NSDictionary *colDescription = columnDescription[ID];
		col.title = colDescription[ColumnTitle];
		NSString *keyPath = colDescription[KeyPathToBind];
		BOOL caseInsensitiveSorting = [colDescription[IsColumnSortingCaseInsensitive] boolValue];
		
		if(keyPath) {
			col.sortDescriptorPrototype = caseInsensitiveSorting ? [NSSortDescriptor sortDescriptorWithKey:keyPath ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] : [NSSortDescriptor sortDescriptorWithKey:keyPath ascending:YES];
		}
		
		[tableView addTableColumn:col];
		
		col.width = col.headerCell.cellSize.width + 10;
		col.minWidth = col.headerCell.cellSize.width ;
		col.hidden = ![colDescription[IsColumnVisibleByDefault] boolValue];
		
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
	
	NSDictionary *cellDescription = self.columnDescription[ID];
	if(!cellDescription) {
		return nil;
	}
	
	NSString *viewID = cellDescription[CellViewID];  /// in no such view exists, we return the right prototype table cell view that is in the sampleTable (in the xib)
	view = [self.viewForCellPrototypes makeViewWithIdentifier:viewID owner:self];
	
	if(view.subviews.count == 0) {
		return  view;					/// hopefully, this won't happen otherwise some views will be missing
	}
	
	NSString *objectValueString = [NSStringFromSelector(@selector(objectValue)) stringByAppendingString:@"."];
	/// we bind elements in this cell to properties of the object is represents.
	/// We could have done it in IB, but it is clearer to do it in code. The bindings are also described in +columnDescription
	NSString *keyPath;
	view.identifier = ID;		/// So that the view will not need to be configured in the future.
	NSTextField *textField = view.textField;
	if(textField) {
		keyPath = [objectValueString stringByAppendingString: cellDescription[KeyPathToBind]];
		[textField bind:NSValueBinding toObject:view withKeyPath:keyPath options:@{NSValidatesImmediatelyBindingOption:@YES}];
		textField.selectable = YES;
		if([cellDescription[IsTextFieldEditable] boolValue]) {
			textField.editable = YES;
			textField.delegate = (id)self;
		}
	}
	
	if(view.imageView) {
		if([view.imageView respondsToSelector:@selector(imageIndex)]) {
			keyPath = [objectValueString stringByAppendingString: cellDescription[ImageIndexBinding]];
			[view.imageView bind:ImageIndexBinding toObject:view withKeyPath:keyPath options:nil];
		}
		if (!view.textField) {		/// the cells only showing an image (no textfield), we bind to the tooltip
			keyPath = [objectValueString stringByAppendingString: cellDescription[KeyPathToBind]];
			[view.imageView bind:NSToolTipBinding toObject:view withKeyPath:keyPath options:nil];
		}
	}
	
	if([view isKindOfClass: GaugeTableCellView.class]) {
		keyPath = [objectValueString stringByAppendingString: cellDescription[KeyPathToBind]];
		[view bind:NSValueBinding toObject:view withKeyPath:keyPath options:nil];
	}
	
	return view;
	
}


- (NSString *)tableView:(NSTableView *)tableView typeSelectStringForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	/// Overridden for performance. We take advantage of the fact that we know which value of an item a table cell shows even if the cell doesn't exist.
	if(tableColumn.isHidden) {
		return nil;
	}
	
	NSDictionary *columnDescription = self.columnDescription;
	
	if(_tableContent && columnDescription) {
		NSDictionary *dic = columnDescription[tableColumn.identifier];
		NSString *keyPath = dic[KeyPathToBind];
		if(![_tableContent.sortDescriptors.firstObject.key isEqualToString:keyPath]) {
			/// We don't use a column for type selection if it's not the first one used for sorting.
			return nil;
		}
		if(![dic[CellViewID] isEqualToString:@"imageCellView"]) {
			/// This type of column does not show any text (or number), so we don't use it
			if([_tableContent.arrangedObjects count] > row) {
				id itemAtRow = _tableContent.arrangedObjects[row];
				if(keyPath) {
					id value = [itemAtRow valueForKeyPath:keyPath];
					if(value) {
						if([value isKindOfClass:NSString.class]) {
							return value;
						}
						return [NSString stringWithFormat:@"%@", value];
					} else {
						return @"";
					}
				}
			}
		}
	}
	return nil;
}

#pragma mark - column visibility and width

- (BOOL)shouldMakeTableHeaderMenu {
	return NO;
}


- (nullable NSArray<NSTableColumn *> *)visibleColumns {
	return [self.tableView.tableColumns filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSTableColumn *column, NSDictionary<NSString *,id> * _Nullable bindings) {
		return !column.isHidden;
	}]];
}


- (BOOL)canHideColumn:(NSTableColumn *)column {
	return YES;
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	NSTableView *tableView = self.tableView;
	NSTableHeaderView *headerView = tableView.headerView;
	if(menu == headerView.menu) {		/// we populate the menu with items representing the columns that the user can show/hide.
		[menu removeAllItems];			/// we do it every time the menu appears so that the columns are in the order of the table (the user may have reordered columns)
										/// Even if certain menu item alway appears at the same position in the menu, it's easier to recreate the whole menu than reordering items.
		if([self canSortByMultipleColumns]) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Sort Table…" action:@selector(showSortCriteria:) keyEquivalent:@""];
			item.target = self;
			[menu addItem:item];
		}
		
		/// We add a menu item allowing to hide the clicked column.
		NSString *title = @"Hide Column";
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(hideColumn:) keyEquivalent:@""];
		item.target = self;
		[menu addItem:item];
		[menu addItem:NSMenuItem.separatorItem];
		
		for(NSTableColumn *col in tableView.tableColumns) {
			/// We create a menu allowing to toggle visibility of each column.
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:col.title action:@selector(toggleColumnVisibility:) keyEquivalent:@""];
			item.target = self;
			item.representedObject = col;
			[menu addItem:item];
		}
		
		[menu addItem:NSMenuItem.separatorItem];
		item = [[NSMenuItem alloc] initWithTitle:@"Show All" action:@selector(showAllColumns:) keyEquivalent:@""];
		[menu addItem:item];
	} else if(menu == tableView.menu) {
		/// if the menu is from our tableview's menu (set in IB), we hide its items if there is no clicked row
		for(NSMenuItem *menuItem in menu.itemArray) {
			menuItem.hidden = tableView.clickedRow < 0;
		}
	}
}


- (void)hideColumn:(NSMenuItem *)sender {
	NSTableColumn *column = sender.representedObject;
	if(column && [self canHideColumn:column]) {
		column.hidden = YES;
	}
}

- (void)toggleColumnVisibility:(NSMenuItem *)sender {
	NSTableColumn *column = sender.representedObject;
	if(column) {
		column.hidden = !column.hidden;
	}
}


-(void)showAllColumns:(id)sender {
	for (NSTableColumn *column in self.tableView.tableColumns) {
		column.hidden = NO;
	}
}


- (CGFloat)tableView:(NSTableView *)tableView sizeToFitWidthOfColumn:(NSInteger)column {
	NSTableColumn *theColumn = tableView.tableColumns[column];
	NSSize textSize = theColumn.headerCell.cellSize; 		/// the column should be at least as large as the header text
	CGFloat maxWidth = textSize.width +5;
	
	for (int row = 0; row < tableView.numberOfRows; row++) {
		/// We don't make views, as it would take too long.
		NSTableCellView *cellView = [tableView viewAtColumn:column row:row makeIfNecessary:NO];
		if(cellView.textField) {
			textSize = cellView.textField.cell.cellSize; 		/// do not use view.fittingSize here. It isn't reliable.
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
	NSMutableArray *strings = NSMutableArray.new;

	for (NSTableColumn *column in self.visibleColumns) {
		[strings addObject:[self stringCorrespondingToColumn:column forObject:object]];
	}
	
	return [strings componentsJoinedByString:@"\t"];
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
		
	}
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
		[self.tableView scrollRowToVisible:row];
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
				if([self.tableContent.selectedObjects indexOfObjectIdenticalTo:clickedItem] != NSNotFound) {
					return self.tableContent.selectedObjects;
				}
				return clickedItem == nil? nil : @[clickedItem];
			}
		}
	}
	return self.tableContent.selectedObjects;
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
				/// [self removeSelectedObjects:objects];  // before we remove the objects, we remove them from the selection. This is because the detailed view shows selected samples, which are somehow not removed from the selection after being deleted (although they get removed from the selection at some point).
				[self.undoManager setActionName:actionName];
				[self removeItems:items];
			}
		}];
		return;
	}
	
	[self.undoManager setActionName:actionName];
	[self removeItems:items];
	[AppDelegate.sharedInstance saveAction:self];
	
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
	[AppDelegate.sharedInstance saveAction:self];
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

#pragma mark - cell text editing

- (void)controlTextDidChange:(NSNotification *)notification {
	/// Makes sure the row being edited is visible.
	NSTextField *textField = notification.object;
		NSInteger rowIndex = [self.tableView rowForView:textField];
		if(rowIndex >= 0) {
			[self.tableView scrollRowToVisible:rowIndex];
		}
}


- (void)controlTextDidEndEditing:(NSNotification *)notification {
	NSTextField *textField = notification.object;
	
	NSInteger columnIndex = [self.tableView columnForView:textField];
	NSInteger rowIndex = [self.tableView rowForView:textField];
	if(columnIndex >= 0 && rowIndex >= 0) {
		NSString *actionName =  [self actionNameForEditingCellInColumn: self.tableView.tableColumns[columnIndex] row:rowIndex];
		if(actionName) {
			[self.undoManager setActionName:actionName];
		}
	}
}


/// The action sent by a popup button in a cell
- (IBAction)popupClicked:(NSPopUpButton *)sender {
	NSInteger columnIndex = [self.tableView columnForView:sender];
	NSInteger rowIndex = [self.tableView rowForView:sender];
	NSArray *columns = self.tableView.tableColumns;
	if(columnIndex >= 0 && columnIndex <= columns.count && rowIndex >= 0) {
		[self.undoManager setActionName: [self actionNameForEditingCellInColumn:columns[columnIndex] row:rowIndex]];
	}
}


- (nullable NSString *)actionNameForEditingCellInColumn:(NSTableColumn *)column row:(NSInteger)row {
	return [@"Edit " stringByAppendingString:column.title];
}


#pragma mark - table sorting

TableSortPopover *tableSortPopover;

static NSString *const AscendingOrderKey = @"AscendingOrderKey";
static NSString *const KeypathKey = @"KeypathKey";

/// shows the popover allowing to sort the table according to (visible) columns
- (IBAction)showSortCriteria:(id)sender {
	if(!self.columnDescription) {
		return;
	}
	
	/// The sort criteria we propose correspond to visible columns
	NSArray *visibleColumns = self.visibleColumns;
	
	if(visibleColumns.count < 1) {
		return;
	}
	
	NSArray<NSSortDescriptor *> *sortDescriptors = [visibleColumns valueForKeyPath:@"@unionOfObjects.sortDescriptorPrototype"];
	
	if(sortDescriptors.count < 1) {
		return;
	}
	
	NSArray<NSString *> *keypaths = [sortDescriptors valueForKeyPath:@"@unionOfObjects.key"];
	
	/// We show the sort criteria that were last applied
	NSArray *lastSortCriteria = [NSUserDefaults.standardUserDefaults arrayForKey:[self.tableView.identifier stringByAppendingString:@"_sortCriteria"]];
	
	NSMutableArray *previousSortDescriptors = [NSMutableArray arrayWithCapacity:lastSortCriteria.count];
	
	for(NSDictionary *dic in lastSortCriteria) {
		if([dic isKindOfClass:NSDictionary.class]) {
			NSString *keypath = dic[KeypathKey];
			if(keypath && [keypaths containsObject:keypath]) {
				[previousSortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:keypath ascending:[dic[AscendingOrderKey] boolValue]]];
			} else {
				[previousSortDescriptors removeAllObjects];
				break;
			}
		}
	}
	
	if(previousSortDescriptors.count < 1) {
		/// If we could not retrieved sort descriptors, we show a default one based on the first visible column.
		previousSortDescriptors = [NSMutableArray arrayWithObject:sortDescriptors.firstObject];
	}
	
	if(!tableSortPopover) {
		tableSortPopover = TableSortPopover.new;
		tableSortPopover.behavior = NSPopoverBehaviorTransient;
	}
	
	NSArray<NSString *> *columnTitles = [visibleColumns valueForKeyPath:@"@unionOfObjects.title"];
	[tableSortPopover.sortCriteriaEditor configureWithSortDescriptors:sortDescriptors
														titles:columnTitles];
	tableSortPopover.sortCriteriaEditor.sortDescriptors = previousSortDescriptors;
	
	tableSortPopover.sortAction = @selector(applySort:);
	tableSortPopover.sortActionTarget = self;
	NSTableHeaderView *headerView = self.tableView.headerView;
	[tableSortPopover showRelativeToRect:headerView.bounds ofView:headerView preferredEdge:NSMaxYEdge];
	NSVisualEffectView *popoverFrame = (NSVisualEffectView *)tableSortPopover.contentViewController.view.superview;
	if([popoverFrame respondsToSelector:@selector(material)]) {
		popoverFrame.material = NSVisualEffectMaterialContentBackground;
	}
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


- (void)flashItem:(id)item {
	NSInteger row = [self.tableContent.arrangedObjects indexOfObjectIdenticalTo:item];
	if(row != NSNotFound) {
		NSTableView *tableView = self.tableView;
		[tableView scrollRowToVisible:row];
		CALayer *flashLayer = self.flashLayer;
		if(flashLayer) {
			flashLayer.hidden = NO;
			NSRect frame = NSIntersectionRect([tableView rectOfRow:row], tableView.visibleRect);
			flashLayer.frame = NSInsetRect(frame, 1, 1); /// This makes the frame more visible in light mode.
			CABasicAnimation* flashAnimation = [CABasicAnimation animationWithKeyPath:@"borderWidth"];
			flashAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
			flashAnimation.fromValue = @(4.0);
			flashAnimation.toValue = @(2.0);
			flashAnimation.duration = 0.5;
			[flashLayer addAnimation:flashAnimation forKey:@"borderWidth"];
		}
	}
}


- (CALayer *)flashLayer {
	if(!_flashLayer) {
		_flashLayer = CALayer.new;
		_flashLayer.borderColor = NSColor.whiteColor.CGColor;
		_flashLayer.borderWidth = 2.0;
		_flashLayer.zPosition = 1000;
		_flashLayer.actions = @{NSStringFromSelector(@selector(bounds)):NSNull.null,
								NSStringFromSelector(@selector(position)):NSNull.null
		};
		[self.tableView.layer addSublayer:_flashLayer];
	}
	return _flashLayer;
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(remove:)) {
		/// we give a contextual title to the menu that removes an item.
		NSString *title = [self removeActionTitleForItems:[self targetItemsOfSender:menuItem]];
		if(title) {
			if(menuItem.topMenu == NSApp.menu) {
				menuItem.title = title;
			}
			menuItem.hidden = NO;
			return YES;
		}
		menuItem.title = @"Delete";
		menuItem.hidden = YES;
		/// absence of title means there is nothing to remove, so we disable the menu item
		/// (which in this case should be from the main application menu, as we hide all items from the contextual menu if there is no clicked item)
		return NO;
	}
	
	if(menuItem.action == @selector(rename:)) {
		/// we give a contextual title to the menu that renames an item.
		id item = [self targetItemsOfSender:menuItem].firstObject;
		if([self canRenameItem:item]) {
			if(menuItem.topMenu == NSApp.menu) {
				menuItem.title = [@"Rename " stringByAppendingString: [self nameForItem:[self targetItemsOfSender:menuItem].firstObject]];
			}
			menuItem.hidden = NO;
			return YES;
		}
		menuItem.hidden = YES;
		return NO;
	}
	
	if(menuItem.action == @selector(showSortCriteria:)) {
		return [self canSortByMultipleColumns];
	}
	
	if(menuItem.action == @selector(moveSelectionByStep:)) {
		return self.tableContent.selectedObjects.count > 0;
	}
	
	NSInteger clickedRow = self.tableView.clickedRow;

	if(menuItem.action == @selector(copy:)) {
		if(menuItem.topMenu == self.tableView.menu) {
			return clickedRow >= 0;
		}
		return self.columnDescription && self.tableContent.selectedObjects.count > 0;
	}
	
	if(menuItem.action == @selector(hideColumn:)) {
		NSArray *visibleColumns = self.visibleColumns;
		if(visibleColumns.count > 1) {
			NSTableView *tableView = self.tableView;
			NSTableHeaderView *headerView = tableView.headerView;
			NSPoint clickPoint = [headerView convertPoint:NSApp.currentEvent.locationInWindow fromView:nil];
			NSInteger clickedCol = [headerView columnAtPoint:clickPoint];
			NSTableColumn *clickedColumn = (clickedCol < 0 || clickedCol >= tableView.numberOfColumns)?
			visibleColumns.lastObject : tableView.tableColumns[clickedCol];
				
			if([self canHideColumn:clickedColumn]) {
				menuItem.title = [@"Hide " stringByAppendingFormat:@"\"%@\"", clickedColumn.title];
				menuItem.representedObject = clickedColumn;
				return YES;
			}
		}
		menuItem.title = @"Can't hide column";
		return NO;
	}
	
	if(menuItem.action == @selector(toggleColumnVisibility:)) {
		NSTableColumn *column = menuItem.representedObject;
		menuItem.state = !column.isHidden;
		BOOL canHideColumn = YES;
		if(!column.isHidden) {
			/// We can't hide a column if there is not more than 1 visible column
			canHideColumn = self.visibleColumns.count > 1 && [self canHideColumn:column];
		}
		menuItem.hidden = !canHideColumn;
		return canHideColumn || column.isHidden;
	}
	
	if(menuItem.action == @selector(showAllColumns:)) {
		return self.visibleColumns.count < self.tableView.tableColumns.count;
	}
	
	return YES;
}


- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	if(_flashLayer) {
		self.flashLayer.hidden = YES;
	}
}


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


- (void)dealloc {
	/// This removes ourselves as observer
	self.filterButton = nil;
}

#pragma mark - recording and restoring selection

- (void)recordSelectedItemsAtKey:(NSString *)subKey maxRecorded:(NSUInteger)maxRecorded {
	NSArrayController *tableContent = self.tableContent;
	NSArray *selectedObjects = tableContent.selectedObjects;
	
	UserDefaultKey key = self.userDefaultKeyForSelectedItemIDs;
	NSMutableDictionary *dic = [NSUserDefaults.standardUserDefaults dictionaryForKey:key].mutableCopy;
	if(!dic) {
		dic = NSMutableDictionary.new;
	}
	[tableContent.managedObjectContext obtainPermanentIDsForObjects:selectedObjects error:nil];
	NSArray *selectedItemIDs = [selectedObjects valueForKeyPath:@"@unionOfObjects.objectID.URIRepresentation.lastPathComponent"];
	NSInteger count = selectedItemIDs.count;
	if(count > 0) {
		if(maxRecorded > 0 && count > maxRecorded) {
			selectedItemIDs = [selectedItemIDs objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, maxRecorded)]];
		}
		dic[subKey] = selectedItemIDs;
	} else {
		[dic removeObjectForKey:subKey];
	}
	[NSUserDefaults.standardUserDefaults setObject:dic forKey:key];
}


- (NSString *)userDefaultKeyForSelectedItemIDs {
	return [@"selected_" stringByAppendingString: self.entityName];
}


- (void)restoreSelectedItemsAtKey:(NSString *)subKey {
	UserDefaultKey key = self.userDefaultKeyForSelectedItemIDs;
	NSDictionary *dic = [NSUserDefaults.standardUserDefaults dictionaryForKey:key];
	if(dic) {
		NSArray *itemIDs = dic[subKey];
		if([itemIDs isKindOfClass:NSArray.class]) {
			NSString *prefix = self.URIStringPrefix;
			if(!prefix) {
				return;
			}
			NSArrayController *tableContent = self.tableContent;
			NSMutableArray *selectedItems = NSMutableArray.new;
			for(NSString *itemID in itemIDs) {
				NSString *longID = [prefix stringByAppendingString:itemID];
				id object = [tableContent.managedObjectContext objectForURIString:longID expectedClass:nil];
				if(object) {
					[selectedItems addObject:object];
				} else {
					return;
				}
			}
			if(selectedItems.count > 0 && [tableContent setSelectedObjects:selectedItems]) {
				[self.tableView scrollRowToVisible:self.tableView.selectedRow];
			}
		}
	}
}


- (void)recordSelectedItems {
	
}


- (void)restoreSelectedItems {
	
}


- (NSString *)URIStringPrefix {
	if(!_URIStringPrefix) {
		NSManagedObject *anObject = [self.tableContent.content firstObject];
		if([anObject respondsToSelector:@selector(objectID)]) {
			NSError *error;
			NSManagedObjectID *objectID = anObject.objectID;
			if(objectID.isTemporaryID) {
				[anObject.managedObjectContext obtainPermanentIDsForObjects:@[anObject] error:&error];
			}
			if(!error) {
				_URIStringPrefix = objectID.URIRepresentation.URLByDeletingLastPathComponent.absoluteString;
			}
		}
	}
	return _URIStringPrefix;
}


# pragma mark - filtering

static void * const filterChangedContext = (void*)&filterChangedContext;

- (void)setFilterButton:(NSButton *)filterButton {
	if(_filterButton) {
		[self.tableContent removeObserver:self forKeyPath:NSStringFromSelector(@selector(filterPredicate))];
	}
	_filterButton = filterButton;
	if(filterButton) {
		[self.tableContent addObserver:self
							forKeyPath:NSStringFromSelector(@selector(filterPredicate))
							   options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
							   context:filterChangedContext];

		if(!_filterButton.action) {
			_filterButton.action = @selector(filterButtonAction:);
			_filterButton.target = self;
		}
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == filterChangedContext) {
		self.filterButton.image = self.filterButtonImage;
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}
	

- (NSImage *)filterButtonImage {
	return self.tableContent.filterPredicate == nil? self.filterButtonImageInactive : self.filterButtonImageActive;
}


- (NSImage *)filterButtonImageActive {
	if(!_filterButtonImageActive) {
		_filterButtonImageActive = [NSImage imageNamed:@"filterButton On"];
	}
	return _filterButtonImageActive;
}


- (NSImage *)filterButtonImageInactive {
	if(!_filterButtonImageInactive) {
		_filterButtonImageInactive = [NSImage imageNamed:@"filterButton"];
	}
	return _filterButtonImageInactive;
}


- (void)configurePredicateEditor:(NSPredicateEditor *)predicateEditor {
	
}


- (BOOL)filterUsingPopover {
	return YES;
}

/// Configures and shows the popover allowing to filter the table
/// - Parameter sender: The object that sent this message.
- (void)filterButtonAction:(NSButton *)sender {
	if(!self.filterUsingPopover) {
		return;
	}
	
	if(!filterPopover) {
		
		filterPopover = NSPopover.new;
		NSViewController *controller = [[NSViewController alloc] initWithNibName:@"FilterPopover" bundle:nil];
		if(controller) {
			filterPopover.contentViewController = controller;
		} else {
			NSLog(@"Failed to load filter popover!");
			return;
		}
				
		filterPopover.animates = YES;
		filterPopover.behavior = NSPopoverBehaviorTransient;
		NSView *contentView = controller.view;
		
		NSTextField *title = [contentView viewWithTag:1];
		title.stringValue = [NSString stringWithFormat:@"Show only %@s meeting these conditions:", self.entityName.lowercaseString];
		
		NSButton *cancelButton = [contentView viewWithTag:4];
		cancelButton.action = @selector(close);
		cancelButton.target = filterPopover;
		
		NSButton *removeFilterButton = [contentView viewWithTag:5];
		removeFilterButton.action = @selector(removeFilter:);
		removeFilterButton.target = self;
		[removeFilterButton bind:NSEnabledBinding
					   toObject:self.tableContent 
					withKeyPath:NSStringFromSelector(@selector(filterPredicate))
						options:@{NSValueTransformerNameBindingOption: NSIsNotNilTransformerName}];
		
		NSButton *applyFilterButton = [contentView viewWithTag:6];
		applyFilterButton.action = @selector(applyFilter:);
		applyFilterButton.target = self;
	
		NSPredicateEditor *predicateEditor = [contentView viewWithTag:2];
		if(![predicateEditor isKindOfClass:NSPredicateEditor.class]) {
			return;
		}
		
		
		[self configurePredicateEditor:predicateEditor];

	}
	
	
	/// We set the predicate to show in the editor
	NSPredicate *filterPredicate = self.tableContent.filterPredicate;
	if(!filterPredicate) {
		filterPredicate = self.defaultFilterPredicate;
	}
	
	if(filterPredicate.class != NSCompoundPredicate.class) {
		/// we make the search predicate a compound predicate to make sure it shows the "all/any/none" option.
		filterPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[filterPredicate]];
	}
	
	NSView *contentView = filterPopover.contentViewController.view;
	
	NSButton *caseSensitiveButton = [contentView viewWithTag:3];
	caseSensitiveButton.state = filterPredicate.isCaseInsensitive? NSControlStateValueOn : NSControlStateValueOff;
	
	NSPredicateEditor *editor = [contentView viewWithTag:2];
	editor.objectValue = filterPredicate;
		
	[filterPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSMinYEdge];
	
	/// We remove the visual effect of the popover, as this doesn't go well with the predicate editor.
	/// We must do it after the popover is set to show, otherwise the visual effect view is not in place.
	NSVisualEffectView *popoverFrame = (NSVisualEffectView *)contentView.superview;
	if([popoverFrame respondsToSelector:@selector(material)]) {
		popoverFrame.material = NSVisualEffectMaterialContentBackground;
	}
}


/// Applies the filter predicate defined by the `filterPopover` to the table.
-(void)applyFilter:(id)sender {
	NSView *contentView = filterPopover.contentViewController.view;
	NSPredicateEditor *editor = [contentView viewWithTag:2];
	NSPredicate *filterPredicate = editor.predicate;
	
	NSError *error = [SampleSearchHelper errorInFieldsOfEditor:editor];
	if(error) {
		[[NSAlert alertWithError:error] beginSheetModalForWindow:editor.window completionHandler:^(NSModalResponse returnCode) {
					
		}];
		return;
	}
	
	NSButton *caseSensitiveButton = [contentView viewWithTag:3];
	
	if(caseSensitiveButton.state == NSControlStateValueOn) {
		filterPredicate = filterPredicate.caseInsensitivePredicate;
	}
	
	[self applyFilterPredicate:filterPredicate];
	
	[filterPopover close];
}


-(void)applyFilterPredicate:(NSPredicate *)filterPredicate {
	if([filterPredicate isEqualTo:self.tableContent.filterPredicate]) {
		[self.tableContent rearrangeObjects];
	} else {
		self.tableContent.filterPredicate = filterPredicate;
	}
}


/// Removes the current filter of the table.
-(void)removeFilter:(id)sender {
	[filterPopover close];
	[self applyFilterPredicate:nil];
}



@end



