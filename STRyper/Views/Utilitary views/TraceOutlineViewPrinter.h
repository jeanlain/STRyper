//
//  TraceOutlineViewPrinter.h
//  STRyper
//
//  Created by Jean Peccoud on 08/07/2025.
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
#import "TraceOutlineView.h"

NS_ASSUME_NONNULL_BEGIN

/// A view designed to print rows of a ``TraceOutlineView``.
///
/// The `TraceOutlineViewPrinter` is inited with the view to print via ``initWithView:``,
/// hence it typically serves for a single printing session.
///
/// This class does not print the rows actually shown by the outline view specified in ``initWithView:``.
/// It prints rows returned by ``TraceOutlineViewDelegate/outlineView:printableRowViewForItem:clipToVisibleWidth:``.
/// All rows are printed, but they are clipped horizontally to reproduce the clipping by the outline view's superview.
@interface TraceOutlineViewPrinter : NSView

/// Notes: implementing the printing methods in an NSOutlineView subclass does not
/// prevent the outline view from drawing with its default internal methods on top.
/// Which is why we use an NSView subclass.

/// Inits the printer view with a outline view to print.
/// - Parameter traceOutlineView: The outline view to print.
/// - Important: The `traceOutlineView` must have a `delegate` that implements ``TraceOutlineViewDelegate/outlineView:printableRowViewForItem:clipToVisibleWidth:``.
-(instancetype) initWithView:(TraceOutlineView *)traceOutlineView;

@end

NS_ASSUME_NONNULL_END
