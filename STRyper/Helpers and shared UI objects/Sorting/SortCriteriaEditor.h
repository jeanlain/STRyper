//
//  SortCriteriaEditor.h
//  STRyper
//
//  Created by Jean Peccoud on 23/07/2023.
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


#import <Cocoa/Cocoa.h>
#import "SortCriteriaEditorDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// A view that allows the user to define criteria for sorting objects.
///
/// A `SortCriteriaEditor` can be used to display or generate an array of sort descriptors (`NSSortDescriptor` objects).
/// It represents each sort descriptor as a row, which includes a popup button to select among attributes (key paths) that are available for sorting objects,
/// a segmented control defining the sort order, and buttons to add or remove a sort descriptor (row).
///
/// The order of rows represents the order of the sort criteria by decreasing priority, and can be changed by click & drag.
@interface SortCriteriaEditor : NSView <NSTableViewDelegate, NSTableViewDataSource>

/// The delegate of the receiver.
@property (weak) IBOutlet id<SortCriteriaEditorDelegate> delegate;


/// Configures the receiver with available sort descriptors for sorting, and user-facing titles.
///
/// The `titles` will be those of the menu items of popup buttons allowing the user to define sort criteria.
/// - Important: The `count` of `titles` and `sortDescriptors` must be the same and ≥ 2, otherwise an exception is thrown.
/// - Parameters:
///   - sortDescriptors: The sort descriptors that the receiver will propose, each of which must have a unique `key`.
///   - titles: The titles that will show in the popup button (from top to bottom) allowing the user to select among sort attributes at a given row.
///   Each title must be unique.
- (void)configureWithSortDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors
							  titles:(NSArray<NSString *> *)titles;

/// The sort descriptors that the receiver shows as rows.
///
/// Setting this property reloads the table, such that visible sort criteria match the sort descriptors in the array.
/// The`selector` of each sort descriptor is ignored.
/// - Important: The `key` of each sort descriptor must be used by one of the `sortDescriptors` set in ``configureWithSortDescriptors:titles:``.
/// Otherwise an exception is thrown. 
@property (nonatomic, copy) NSArray<NSSortDescriptor *>* sortDescriptors;

/// The table view that contains the rows representing sort descriptors.
///
/// The table content, its `delegate` and its `datasource` must not be changed as they are set internally.
/// Only visuals attributes may be changed.
@property (nonatomic, readonly) NSTableView *sortCriteriaTable;


/// Convenience method that sets the full dragged rows of a table view as images of dragging items.
///
/// This method should be called within `tableView:draggingSession:willBeginAtPoint:forRowIndexes:`.
/// It sets the image of the session's dragged items as the rows being dragged, with proper positioning.
/// - Parameters:
///   - session: The dragging session.
///   - tableView: The table view whose rows will be dragged.
///   - rowIndexes: The indexes of dragged rows.
///   - screenPoint: The drag point in screen coordinates
+ (void)setRowImagesForDraggingSession:(NSDraggingSession *)session
						 fromTableView:(NSTableView *)tableView
						  atRowIndexes:(NSIndexSet *)rowIndexes
							  forPoint:(NSPoint)screenPoint;

@end

NS_ASSUME_NONNULL_END
