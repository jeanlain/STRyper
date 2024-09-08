//
//  TableHeaderView.h
//  STRyper
//
//  Created by Jean Peccoud on 11/10/2022.
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

/// An `NSTableHeaderView` that only sets cursor rectangles in its visible rect.
///
/// In macOS version 12 and earlier, `NSTableHeaderView`  cursor rectangles are added even if there are in the clipped region 
/// (which is an oversight on Apple's part), and may cause cursor changes on overlapping views.
///
/// This class avoids that by overriding `-addCursorRect:cursor:`.
@interface TableHeaderView : NSTableHeaderView

@end

NS_ASSUME_NONNULL_END
