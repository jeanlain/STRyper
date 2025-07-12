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

/// A row view that makes a designated `NSScrollView` subview as wide as its tableview's `clipView`.
///
/// This class addresses a very specific situation:
/// if a tableview scrolls horizontally and if its rows contain a scrollview, the user may have to scroll two views (the one within the row and the tableview) to see the full content of a row.
///
/// To avoid this, an `STableRowView` makes its subview as wide as its visible rectangle (determined by the width of the tableview's clipview).
///
///
/// ``STRyper`` uses this class for table rows containing ``TraceScrollView`` views.
@interface STableRowView : NSTableRowView

/// The scrollview that should be resized to fit the tableView's clipView width.
///
/// Setting this property makes `embeddedScrollView` a subview of the receiver
/// and removes any previous `embeddedScrollView` from the subviews.
@property (nonatomic) __kindof NSScrollView *embeddedScrollView;

@end

NS_ASSUME_NONNULL_END
