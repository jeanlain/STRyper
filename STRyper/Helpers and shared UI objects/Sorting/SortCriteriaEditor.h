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

/// A view that allows the user to define attributes for sorting objects.
///
/// A `SortCriteriaEditor` can be used to display or generate an array of sort descriptors (`NSSortDescriptor` objects).
/// It represents each sort descriptor as a row, which includes a popup button to selected among attributes (key paths) that are available for sorting objects,
/// a segmented control defining the sort order, and buttons to add or remove a sort descriptor (row).
///
/// The order of rows represents the order of the sort criteria by decreasing priority, and can be changed by click & drag.
@interface SortCriteriaEditor : NSView <NSTableViewDelegate, NSTableViewDataSource>

/// The delegate of the receiver.
@property (weak) IBOutlet id<SortCriteriaEditorDelegate> delegate;


/// Configures the receiver with available key paths for sorting, and corresponding user-friendly titles.
/// - Parameters:
///   - titles: The titles that will show in the popup button (from top to bottom) allowing the user to select among sort attributes at a given row. The array must contain at least two elements, each of which must be unique.
///   - keypaths: The key paths that the user can use for sorting. Each key path corresponds to the element of the `titles` argument at the same index, and must be unique.
-(void)setTitles:(NSArray<NSString *>*)titles forKeyPath:(NSArray<NSString *>*)keypaths;

/// The sort descriptors that the receiver shows.
///
/// The `selector` of each sort descriptor is ignored, but its `key` must belong to the `keypaths` specified in ``setTitles:forKeyPath:``.
@property (nonatomic) NSArray <NSSortDescriptor *>* sortDescriptors;

/// The table view that contains the rows representing sort descriptors.
///
/// The table content should not be modified as it is set internally. Only visuals attributes may be changed.
@property (nonatomic, readonly) NSTableView *sortCriteriaTable;



@end

NS_ASSUME_NONNULL_END
