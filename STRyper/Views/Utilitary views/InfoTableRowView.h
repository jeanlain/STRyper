//
//  InfoTableRowView.h
//  STRyper
//
//  Created by Jean Peccoud on 28/09/2025.
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
#import "InfoOutlineView.h"

NS_ASSUME_NONNULL_BEGIN

/// A row view that work in conjunction to an ``InfoOutlineView`` to draw grid lines only between main sections.
///
/// If the view's superView returns `YES` to ``InfoOutlineView/drawGridForMainSectionsOnly``,
/// the row does not draw its background and is transparent. It only draws the separator.
@interface InfoTableRowView : NSTableRowView

@end

NS_ASSUME_NONNULL_END
