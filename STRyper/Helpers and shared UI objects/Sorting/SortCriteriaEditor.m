//
//  SortCriteriaEditor.m
//  STRyper
//
//  Created by Jean Peccoud on 23/07/2023.
//
//
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


#import "SortCriteriaEditor.h"

@interface SortCriteriaEditor ()

@property (nonatomic) NSArray<NSString *> *titles;  	/// used to provide the content of the popup button (via a binding set in IB) allowing the user to choose the columns used for sorting (based on their titles).

@end


@implementation SortCriteriaEditor {
	__weak IBOutlet NSTableView *sortCriteriaTable;				/// the tableview showing the sort criteria on the sheet (designed in a nib)
																
	/// The dictionaries represented by the rows of the sortCriteriaTable.
	/// We cannot use NSSortDescriptor objects to bind to the table celles, as these objects are immutable.
	NSMutableArray<NSMutableDictionary *> *sortDictionaries;
	NSMutableDictionary *titlesForSortKeys;						/// makes the correspondence between columns titles used for sorting and sort keys in the generated sort descriptors.
	NSMutableDictionary *sortKeysForTitles;
	NSMutableDictionary *selectorNamesForSortKeys;
	NSInteger draggedRow;										/// the index of the row being dragged
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		[self loadSubViewFromNib];
	}
	return self;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if(self) {
		[self loadSubViewFromNib];
	}
	return self;
}


-(void)loadSubViewFromNib {
	if([NSBundle.mainBundle loadNibNamed:@"SortCriteriaEditor" owner:self topLevelObjects:nil]) {
		NSScrollView *scrollView = sortCriteriaTable.enclosingScrollView;
		if(scrollView) {
			scrollView.frame = self.bounds;
			scrollView.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
			[self addSubview:scrollView];
		}
		[sortCriteriaTable registerForDraggedTypes: @[CriteriaDragType]];		/// for when the user drags row to change the sort
	}
}



- (NSTableView *)sortCriteriaTable {
	return sortCriteriaTable;
}


- (NSSize)intrinsicContentSize {
	NSSize size = sortCriteriaTable.intrinsicContentSize;
	size.width = sortCriteriaTable.bounds.size.width;
	return size;
}

/// keys for dictionaries
static NSString *const ascendingOrder = @"ascending";
static NSString *const Title = @"title";


- (void)configureWithSortDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors titles:(NSArray<NSString *> *)titles {
	NSUInteger count = titles.count;
	if(count != sortDescriptors.count) {
		NSException *exception = [NSException exceptionWithName:@"Editor configuration exception." reason:@"Cannot configure the editor. The titles and sort descriptors have different counts." userInfo:nil];
		[exception raise];
		return;
	}
		
	if(count < 1) {
		NSException *exception = [NSException exceptionWithName:@"Editor configuration exception." reason:@"Cannot configure the editor. There are fewer than 1 title." userInfo:nil];
		[exception raise];
		return;
	}
	
	self.titles = titles;
	
	NSArray *keypaths = [sortDescriptors valueForKeyPath:@"@unionOfObjects.key"];

	titlesForSortKeys = [NSMutableDictionary dictionaryWithObjects:titles forKeys:keypaths];
	sortKeysForTitles = [NSMutableDictionary dictionaryWithObjects:keypaths forKeys:titles];
		
	NSMutableArray *selectorNames = [NSMutableArray arrayWithCapacity:count];
	for(NSSortDescriptor *sortDescriptor in sortDescriptors) {
		[selectorNames addObject:NSStringFromSelector(sortDescriptor.selector)];
	}
	selectorNamesForSortKeys = [NSMutableDictionary dictionaryWithObjects:selectorNames forKeys:keypaths];
	
}


- (void)setSortDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors {
	sortDictionaries = [NSMutableArray arrayWithCapacity:sortDescriptors.count];
	for(NSSortDescriptor *sortDescriptor in sortDescriptors) {
		NSString *title = titlesForSortKeys[sortDescriptor.key];
		if(title) {
			NSMutableDictionary *sortCriterion = [NSMutableDictionary dictionaryWithDictionary: @{Title: title,
																								  ascendingOrder: @(sortDescriptor.ascending)
																								}];
			[sortDictionaries addObject:[NSMutableDictionary dictionaryWithDictionary:sortCriterion]];
		} else {
			NSString *reason = [NSString stringWithFormat:@"Cannot show sort descriptor(s). '%@' is not one of the keypaths: %@", sortDescriptor.key, titlesForSortKeys.allKeys];
			NSException *exception = [NSException exceptionWithName:@"Editor sort descriptors exception" reason:reason userInfo:nil];
			[exception raise];
			return;
		}
	}
	[sortCriteriaTable reloadData];
	
	if([self.delegate respondsToSelector:@selector(editorDidChangeSortDescriptors:)]) {
		[self.delegate editorDidChangeSortDescriptors:self];
	}
}


- (NSArray<NSSortDescriptor *> *)sortDescriptors {
	NSMutableArray *sortDescriptors = [NSMutableArray arrayWithCapacity:sortDictionaries.count];
	for(NSDictionary *dic in sortDictionaries) {
		NSString *key = sortKeysForTitles[dic[Title]];
		NSString *selectorName = selectorNamesForSortKeys[key];
		if(!selectorName) {
			selectorName = NSStringFromSelector(@selector(compare:));
		}
		BOOL ascending = [dic[ascendingOrder] boolValue];
		if(key) {
			NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:key
																		 ascending:ascending
																		  selector:NSSelectorFromString(selectorName)];
			[sortDescriptors addObject:descriptor];
		}
	}
	return [NSArray arrayWithArray: sortDescriptors];
}

# pragma mark - datasource methods for the table view defining sort criteria

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return sortDictionaries.count;
}


- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	if(sortDictionaries.count > row) {
		return sortDictionaries[row];
	}
	return nil;
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSTableCellView *view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];		/// all cells of the table are designed in IB
	if([tableColumn.identifier isEqualToString:@"addRemove"]) {
		/// The view showing the buttons allowing to add/remove a sort criterion
		for(NSButton *button in view.subviews) {
			if(button.action == @selector(removeRow:)) {
				/// We don't allow removing all rows (as the user won't be able to add new ones, as the "+" button would be gone.
				button.hidden = sortDictionaries.count <= 1;
			} else {
				/// Once all visible columns are used for sorting, we can't add more rows
				button.enabled = sortDictionaries.count < self.titles.count;
			}
		}
	} else if([tableColumn.identifier isEqualToString:@"sortBy"]) {		/// the first column
		view.textField.stringValue = row == 0? @"Sort by:" : @"then by:";
	} else if([tableColumn.identifier isEqualToString:@"key"]) {
		/// the cell showing the popup button allowing to choose the search key
		NSPopUpButton *popUp = view.subviews.firstObject;
		if([popUp isKindOfClass:NSPopUpButton.class]) {
			popUp.enabled = YES;
			for(NSMenuItem *item in popUp.menu.itemArray) {
				item.enabled = YES;			/// we enable all items because, for unknown reasons, the selected item may sometimes appear as disabled
											/// Note: this doesn't seem necessary, but maybe it was in older macOS versions.
			}
		}
	}
	return view;
}

# pragma mark - adding, removing or reordering criteria


/// Inserts a new row (sort criterion) to the table. Only sent by the "+" button.
- (IBAction)insertRow:(NSButton *)sender {
	NSInteger clickedRow = [sortCriteriaTable rowForView:sender];
	if(clickedRow < 0 || clickedRow >= sortDictionaries.count) {
		return;
	}
	/// we choose a title among those not already used for sorting.
	NSArray *usedTiles = [sortDictionaries valueForKeyPath:[@"@unionOfObjects." stringByAppendingString:Title]];
	NSString *title = self.titles.firstObject;
	for(title in self.titles) {
		if(![usedTiles containsObject:title]) {
			break;
		}
	}
	if(title == nil) {
		return;
	}
	NSMutableDictionary *sortCriterion = [NSMutableDictionary dictionaryWithDictionary: @{Title:title,
																						  ascendingOrder: @YES
																						}];
	
	[sortDictionaries insertObject:sortCriterion atIndex:clickedRow+1];
	
	[sortCriteriaTable insertRowsAtIndexes: [NSIndexSet indexSetWithIndex: clickedRow+1] withAnimation:NSTableViewAnimationSlideUp];
	
	/// we makes sure that the "remove" buttons show as they should
	[sortCriteriaTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, sortCriteriaTable.numberOfRows)] columnIndexes:[NSIndexSet indexSetWithIndex:3]];
		
	if([self.delegate respondsToSelector:@selector(editor:didAddRowAtIndex:)]) {
		[self.delegate editor:self didAddRowAtIndex:clickedRow+1];
	}
}


/// Removes a row (sent by the "–" button at that row.)
- (IBAction)removeRow:(NSButton *)sender {
	if(sortDictionaries.count < 2) {
		/// we can't remove the last sort criterion
		return;
	}
	
	NSInteger clickedRow = [sortCriteriaTable rowForView:sender];
	if(clickedRow < 0 || clickedRow >= sortDictionaries.count) {
		return;
	}
		
	[sortDictionaries removeObjectAtIndex:clickedRow];
	
	[sortCriteriaTable removeRowsAtIndexes:[NSIndexSet indexSetWithIndex: clickedRow]  withAnimation:NSTableViewAnimationSlideUp];
	
	if(clickedRow == 0) {
		/// if the first row was removed, the new row must have "Sort by" in the first column
		[sortCriteriaTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:0] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
	}
	
	/// we make sure that the "add" buttons have their correct state
	[sortCriteriaTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, sortCriteriaTable.numberOfRows)] columnIndexes:[NSIndexSet indexSetWithIndex:3]];

	if([self.delegate respondsToSelector:@selector(editor:didRemoveRowAtIndex:)]) {
		[self.delegate editor:self didRemoveRowAtIndex:clickedRow];
	}
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	/// we're the delegate of the popup buttons' menus allowing to choose the attributes by which to sort.
	/// we disable the items corresponding to titles already used for sorting in other rows.
	/// We don't use `validateMenuItem:` because it isn't called even after we set set the target and action of items.
	NSArray *usedTitles = [sortDictionaries valueForKeyPath:[@"@unionOfObjects." stringByAppendingString:Title]];
	for (NSMenuItem *item in menu.itemArray) {
		item.enabled = item.state == NSControlStateValueOn || ![usedTitles containsObject:item.title];
	}
}

#pragma mark - drag & drop of a row to change the order of sort criteria

static NSString *const CriteriaDragType = @"org.jpeccoud.stryper.criteriaDragType";

- (void)resetCursorRects {
	if(sortCriteriaTable.numberOfRows > 1) {
		/// We add a rectangle on the left column to show a open hand cursor, indicating that rows can be dragged to reorder sort criteria
		/// We only show this on the left column, because it is the only one that cannot be clicked (no button)
		/// This is only relevant if there are several rows
		NSRect rect = sortCriteriaTable.bounds;
		rect.size.width = sortCriteriaTable.tableColumns.firstObject.width +10;
		[self addCursorRect:rect cursor:NSCursor.openHandCursor];
	}
}


- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
	NSPasteboardItem *item = NSPasteboardItem.new;
	/// We actually don't use the pasteboard, as we just record the dragged row at the beginning of the drag session.
	[item setString:@"" forType:CriteriaDragType];
	return item;
}


- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes {
	
	draggedRow = rowIndexes.firstIndex;
	if(NSCursor.currentCursor != NSCursor.closedHandCursor) {
		[NSCursor.closedHandCursor push];
	}
	
	[self.class setRowImagesForDraggingSession:session fromTableView:tableView atRowIndexes:rowIndexes forPoint:screenPoint];
	
}


+ (void)setRowImagesForDraggingSession:(NSDraggingSession *)session fromTableView:(NSTableView *)tableView atRowIndexes:(NSIndexSet *)rowIndexes forPoint:(NSPoint) screenPoint {
	
	/// We prepare row images representing items being dragged
	NSMutableArray *imageComponents = [NSMutableArray arrayWithCapacity:rowIndexes.count];
	NSPoint viewPoint = [tableView.window convertPointFromScreen:screenPoint];
	viewPoint = [tableView convertPoint:viewPoint fromView:nil];
	NSPointPointer ptr = &screenPoint;

	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
		NSImage *rowImage = [tableView dragImageForRowsWithIndexes:[NSIndexSet indexSetWithIndex:idx] tableColumns:tableView.tableColumns event:NSEvent.new offset:ptr];
			if(rowImage) {
				[imageComponents addObject:rowImage];
			}
	}];
	
	/// we set the image components of the dragging items
	[session enumerateDraggingItemsWithOptions:NSDraggingItemEnumerationConcurrent
									   forView:nil
									   classes:@[NSPasteboardItem.class]
								 searchOptions:NSDictionary.new
									usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
		if(idx < imageComponents.count) {
			NSImage *rowImage = imageComponents[idx];
			NSSize imageSize = rowImage.size;
			[draggingItem setDraggingFrame:NSMakeRect(-viewPoint.x, draggingItem.draggingFrame.origin.y, imageSize.width, imageSize.height)
								  contents:rowImage];
		} else {
			*stop = true;
		}
	}];
}


- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
	if(NSCursor.currentCursor != NSCursor.closedHandCursor) {
		/// it's not clear why, but upon first drag in the session, the arrow cursor is set. So we restore the appropriate cursor
		[NSCursor.closedHandCursor push];
	}
	if(row == draggedRow || row-1 == draggedRow || dropOperation == NSTableViewDropOn) {
		return NSDragOperationNone;
	}
	return NSDragOperationMove;
}


- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
	if(sortDictionaries.count <= draggedRow) {
		return NO;
	}
	
	NSMutableDictionary *movedItem = sortDictionaries[draggedRow];
	if(draggedRow < row) {
		row--;
	}
	
	[sortDictionaries removeObjectAtIndex:draggedRow];
	[sortDictionaries insertObject:movedItem atIndex:row];
	
	NSAnimationContext *animationContext = NSAnimationContext.currentContext;
	animationContext.duration = 0.2;			/// the default move animation is way too slow.
	[NSAnimationContext beginGrouping];
	[tableView moveRowAtIndex:draggedRow toIndex:row];
	[NSAnimationContext endGrouping];
	
		/// we reload the first cell of every row to make sure that the text shows "Sort by:" then "then by:"
		/// We don't reload the whole table, as this would stop the animation
	[tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, tableView.numberOfRows)] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
		
	if([self.delegate respondsToSelector:@selector(editor:didMoveRowFormIndex:toIndex:)]) {
		[self.delegate editor:self didMoveRowFormIndex:draggedRow toIndex:row];
	}
	
	return YES;
}


@end
