//
//  TraceOutlineView.h
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

#import <Cocoa/Cocoa.h>
#import "TraceOutlineViewDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// An `OutlineView` that forwards keyDown events and message related to row selection.
///
/// A `TraceOutlineView` is not allowed to select rows, it forwards messages
/// to its ``delegate`` when these messages relate to row selection.
/// The delegate can then decide what do with these messages.
///
/// - Important: this class assumes that the ``delegate`` does not allow selecting rows from the outline view.
@interface TraceOutlineView : NSOutlineView <NSMenuItemValidation, CALayerDelegate>

/// The delegate of the receiver.
@property(weak, nullable) id<TraceOutlineViewDelegate> delegate;

/// The visible rectangle of the outline view that is below its `headerView`.
@property(nonatomic, readonly) NSRect visibleRectBelowHeader;

/// The point of the outline view that is at the bounds origin of its parent `clipView`.
@property(nonatomic, readonly) NSPoint scrollPoint;

/// The point of the outline view that is at the bottom left of its parent `clipView`.
@property(nonatomic, readonly) NSPoint bottomLeftPoint;

@end

NS_ASSUME_NONNULL_END
