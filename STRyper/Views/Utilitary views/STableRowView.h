//
//  STableRowView.h
//  STRyper
//
//  Created by Jean Peccoud on 18/04/2023.
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



@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

/// A row view that makes a designated subview as wide as its tableview's `superView`.
///
/// An `STableRowView` makes sure that its designated ``mainSubview`` is not clipped by the tableView's `superView` (which normally is a clipview).
///
/// For instance, if the row view had a scrollview fitting its whole frame as a subview,
/// the user may have to scroll two views (this scrollview and the tableview's) to see the full content of a row.
///
/// To avoid this, an `STableRowView` makes its ``mainSubview`` as wide as its visible rectangle (determined by the width of the tableview's clipview).
///
/// ``STRyper`` uses this class for table rows containing ``TraceScrollView`` views.
@interface STableRowView : NSTableRowView

/// The subview that should be resized to fit the tableView's clipView width.
///
/// Setting this property makes `mainSubview` a subview of the receiver
/// and removes the previous `mainSubview` from the subviews.
@property (nonatomic) __kindof NSView *mainSubview;

@end

NS_ASSUME_NONNULL_END
