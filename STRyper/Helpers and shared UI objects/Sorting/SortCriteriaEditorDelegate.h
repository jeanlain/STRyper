//
//  TableSortPopoverDelegate.h
//  STRyper
//
//  Created by Jean Peccoud on 22/07/2023.
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


@class SortCriteriaEditor;

NS_ASSUME_NONNULL_BEGIN

/// Optional methods that the delegate of a ``SortCriteriaEditor`` object can implement.
@protocol SortCriteriaEditorDelegate <NSObject>

@optional

/// Called after the user has added a row to the editor.
/// - Parameters:
///   - editor: The object that sent this message.
///   - index: The index of the row that was added.
-(void)editor:(SortCriteriaEditor *)editor didAddRowAtIndex:(NSUInteger)index;

/// Called after the user has removed a row from the editor.
/// - Parameters:
///   - editor: The object that sent this message.
///   - index: The index of the row that was removed.
-(void)editor:(SortCriteriaEditor *)editor didRemoveRowAtIndex:(NSUInteger)index;

/// Called after the user moved a row in the editor.
/// - Parameters:
///   - editor: The object that sent this message.
///   - source: The original index of the row that was removed.
///   - destination: The current location of the row
-(void)editor:(SortCriteriaEditor *)editor didMoveRowFormIndex:(NSUInteger)source toIndex:(NSUInteger)destination;

/// Called after the sort descriptors of the editor have been successfully changed via `setSortDescriptors`.
/// - Parameters:
///   - editor: The object that sent this message.
-(void)editorDidChangeSortDescriptors:(SortCriteriaEditor *)editor;


@end

NS_ASSUME_NONNULL_END
