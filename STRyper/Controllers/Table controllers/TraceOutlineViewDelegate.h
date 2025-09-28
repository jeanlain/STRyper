//
//  TraceOutlineViewDelegate.h
//  STRyper
//
//  Created by Jean Peccoud on 10/08/2025.
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

#import <Foundation/Foundation.h>
@class TraceOutlineView;

NS_ASSUME_NONNULL_BEGIN

/// Methods that the delegate of a ``TraceOutlineView`` must implement.
@protocol TraceOutlineViewDelegate <NSOutlineViewDelegate>


/// Sent by a ``TraceOutlineView`` when it receives a `keyDown:`event.
///
/// This method allows, for instance, forwarding arrow key presses to select previous/next objects
/// from a a source that provides content to the `TraceOutlineView`.
/// - Parameters:
///   - outlineView: The object that sent this message.
///   - event: The `keyDown` event.
-(void)outlineView:(TraceOutlineView *)outlineView keyDown:(NSEvent *)event;


/// Sent by a ``TraceOutlineView`` when it receives a `selectAll:`message.
/// - Parameter sender: The object that sent this message.
-(void)selectAll:(id)sender;


/// Sent by a ``TraceOutlineView`` when it receives a `deselectAll:`message.
/// - Parameter sender: The object that sent this message.
-(void)deselectAll:(id)sender;

/// Returns whether a `selectAll:` action is valid.
///
/// This method is used by the `TraceOutlineView` to validate a menu item having the `selectAll:` action.
/// The delegate thus returns whether the menu item should be enabled.
/// - Parameter traceOutlineView: The object that sent this message.
-(BOOL)canSelectItemsForOutlineView:(TraceOutlineView *)traceOutlineView;


/// Returns a row view that is suitable for drawing during a print operation.
/// 
/// The returned view has no superview but has all  the subviews expected for the `outlineView`.
/// These subviews are set with a light appearance. Opaque background colors are replaced with white (if possible).
/// Buttons and scrollers are hidden.
/// 
/// - Important: The returned view is intended for printing (drawing) only. When the method is called successively in the same print operation,
/// it returns the same `NSTableRowView` instance for equivalent row views.
/// Modification to the returned view, such as changing its frame, should therefore be avoided.
/// - Parameters:
///   - outlineView: The outline view that serves as model for the row view.
///   - item: The item for which the row view should be generated.
///   - clipped: Whether the row view width and position of subviews should be adjusted to mimmic horizontal clipping by the `outlineView`'s superview(s).
///   If set to `NO`, the returned view occupies the full width of the `outlineView`, extending beyond the visible rectangle.
- (NSTableRowView *)outlineView:(TraceOutlineView *)outlineView printableRowViewForItem:(id)item clipToVisibleWidth:(BOOL)clipped;

@end

NS_ASSUME_NONNULL_END
