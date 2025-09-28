//
//  InfoOutlineView.h
//  STRyper
//
//  Created by Jean Peccoud on 28/09/2025.

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

/// An outline view that only draws horizontal grid lines between top parents
///
/// This view works in conjunction to ``InfoTableRowView`` to mimic the info panel of the macOS Finder, which only
/// draws horizontal separator between sections, not between a parent row and a child row or between children rows.
///
/// This behaviour is enabled by `` drawGridForMainSectionsOnly`` returning `YES` and the outline view
/// being set to draw the horizontal grid via its `gridStyleMask` property.
///
/// - Important: if ``drawGridForMainSectionsOnly`` is `YES`,
/// each row view must inherit from ``STableRowView``.
/// Otherwise,  grid lines will be drawn after each row, according to the `gridStyleMask` property.
@interface InfoOutlineView : NSOutlineView

/// Whether the outline views draws the grid only between main section (top-level parents).
///
/// Important: if this property is `YES`, each row view must inherit from ``InfoTableRowView``.
/// Otherwise, default grid lines will be drawn after each row.
/// However, no grid line will be drawn after the last row, regardless of the row view subclass.
@property (nonatomic) BOOL drawGridForMainSectionsOnly;

@end

NS_ASSUME_NONNULL_END
