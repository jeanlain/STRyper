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



#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A row view that makes its first subview as wide as its tableview's clipview.
///
/// This class addresses a very specific situation:
/// if a tableview scrolls horizontally and if its rows contain scrollviews, the user may have to scroll two views (the one within the row and the tableview) to see the full content of a row.
///
/// To avoid this, an `STableRowView` makes its subview as wide as its visible rectangle (determined by the width of the tableview's clipview).
///
/// IMPORTANT: this view does not check which of its subviews is a scrollview. It will resize its first subview regardless of its class.
///
/// ``STRyper`` uses this class for table rows containing ``TraceScrollView`` views.
@interface STableRowView : NSTableRowView



@end

NS_ASSUME_NONNULL_END
