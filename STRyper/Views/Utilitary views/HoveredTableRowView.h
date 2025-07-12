//
//  HoveredTableRowView.h
//  STRyper
//
//  Created by Jean Peccoud on 23/02/2023.
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

/// An NSTableRowView that can shows a button at its right when it is hovered.
///
/// A `HoveredTableRowView` implements the same behaviour as group rows showing a "+" button in the left sidebar of Apple Mail.
/// Its ``hoveredButton`` is a button that only shows when the view is hovered.
///
/// The button remains hidden if the row view is not a group row (groupRowStyle must return YES).
///
/// If the view also shows a disclosure triangle (in an outline view) this triangle must be at the right of the row (group row style).
/// Otherwise, the ``hoveredButton`` remains hidden.
@interface HoveredTableRowView : NSTableRowView

/// The button that should appear when the view is hovered.
///
/// The button is resized to occupy the whole height of the row.
@property (nonatomic, nullable) IBOutlet NSButton *hoveredButton;

@end

NS_ASSUME_NONNULL_END
