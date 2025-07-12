//
//  TraceViewTablePrinter.h
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

NS_ASSUME_NONNULL_BEGIN

/// A view designed to print rows of an outline view showing trace views (the type managed by the ``DetailedViewController``).
///
/// Before printing, the `TraceViewTablePrinter` is inited with the table to print via ``initWithTable:``,
/// hence it typically serves once. This class calls outline view delegate and datasource methods to generate row views when it renders pages.
/// It does not print the views actually shown by the outline view that was specified in ``initWithTable:``.
/// The outline view delegate and datasource methods called will have `nil` for the `outlineView` parameter.
@interface TraceViewTablePrinter : NSView

/// Inits the view given a outline view to print.
/// - Parameter traceTable: The outline view to print.
/// - Important: The `traceTable` must have a `delegate` and a `datasource` that implement
///  delegates and datasources methods to compute the height of rows and to provide row views and cell views for items.
-(instancetype) initWithTable:(NSOutlineView *)traceTable;

@end

NS_ASSUME_NONNULL_END
