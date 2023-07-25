//
//  TableSortPopover.h
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


#import <Cocoa/Cocoa.h>
#import "SortCriteriaEditor.h"
#import "SortCriteriaEditorDelegate.h"

NS_ASSUME_NONNULL_BEGIN


/// A popover that allows the user to define sort criteria (columns) for a table view.
///
/// A `TableSortPopover` uses a ``sortCriteriaEditor`` to show sort criteria, has a cancel button to dismiss it,
/// and a "Sort Table" button whose action and target can be set.
///
/// The dimensions of the popover automatically adjust to the size of its sort criteria editor.
@interface TableSortPopover : NSPopover <SortCriteriaEditorDelegate>


/// The ``SortCriteriaEditor``instance allowing the user to edit sort criteria.
@property (nonatomic, readonly) SortCriteriaEditor *sortCriteriaEditor;

/// The action sent by the ""Sort Table" button.
@property (nonatomic) SEL sortAction;

/// The target of ""Sort Table" button.
@property (nonatomic, weak) id sortActionTarget;


@end

NS_ASSUME_NONNULL_END
