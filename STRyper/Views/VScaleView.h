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




#import "Trace.h"
#import "TraceView.h"

NS_ASSUME_NONNULL_BEGIN

/// A view that shows the vertical (fluorescence) scale of a ``TraceView`` and allows the user to modify this scale by clicking & dragging the mouse.
///
///	A `VScaleView` shows tick-marks and labels. Theses constitute the vertical axis of the plot containing fluorescent curves drawn by the trace view.
///	The labels represent fluorescent levels of traces.
///
///	IMPORTANT: the positioning of the labels assumes that is bottom edge of the `VScaleView` is at the bottom edge of its superview.
///	To be properly positioned, the `VSCaleView` must be a subview of a ``TraceScrollView``.
@interface VScaleView : NSView

/// Note: we don't use a subclass of NSRulerView as a an NSRulerView is redrawn during scroll, which we don't want.

/// The ``TraceView`` that is associated with the receiver.
///
/// This property is set by the ``TraceScrollView`` when it gets its document view.
@property (weak, nonatomic) TraceView *traceView;

/// Returns the fluorescence level of the highest peak found in set of traces within a given range.
///
/// While fluorescent levels are coded as short integer number (see ``Trace``), this method returns a float as the result is often used in floating point operations.
///
/// This method uses the ``Trace/peaks`` attribute of traces, and returns 0 if no peak is found in the `range`.
/// - Parameters:
///   - traces: The trace in which to look for peaks.
///   - range: The range within which peaks are considered.
///   - useRawData: Whether the fluorescence data to use should be retrieved from ``Trace/rawData``. If `NO`, the data is that returned by ``Trace/adjustedDataMaintainingPeakHeights:`` without maintaining peak heights.
///   - ignoreCrosstalk: Wether peaks resulting from crosstalk are ignored.
+ (float) maxFluoOf: (NSArray *)traces inRange: (BaseRange)range useRawData:(BOOL)useRawData ignoreCrosstalk:(BOOL)ignoreCrosstalk;


@end

NS_ASSUME_NONNULL_END
