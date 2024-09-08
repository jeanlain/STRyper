//
//  VScaleView.h
//  STRyper
//
//  Created by Jean Peccoud on 03/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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




#import "TraceView.h"

NS_ASSUME_NONNULL_BEGIN

/// A view that shows the vertical (fluorescence) scale of a ``TraceView`` and allows the user to modify this scale by clicking & dragging the mouse.
///
/// A `VScaleView` shows tick-marks and labels. Theses constitute the vertical axis of the plot containing fluorescent curves drawn by the trace view.
/// The labels represent fluorescent levels of traces.
///
/// - Important: the positioning of the labels assumes that the bottom edge of the `VScaleView` is at the bottom edge of its superview.
/// To be properly positioned, the `VSCaleView` must be a subview of a ``TraceScrollView``. This scroll view creates a `VScaleView` when a ``TraceView`` is set as its `documentView`.
@interface VScaleView : NSView

/// Note: we don't use a subclass of `NSRulerView` as this view is not a ruler.

/// The ``TraceView`` that is associated with the receiver.
@property (weak, nonatomic, readonly) TraceView *traceView;

/// The desired width of the view.
///
/// The default is 30.0. The effective value is constrained to the range [0, 100];
@property (nonatomic) float width;

@end

NS_ASSUME_NONNULL_END
