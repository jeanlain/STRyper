//
//  PeakLabel.h
//  STRyper
//
//  Created by Jean Peccoud on 05/01/13.
//  Copyright (c) 2013 Jean Peccoud. All rights reserved.
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

#import "ViewLabel.h"
#import "Trace.h"

@class FragmentLabel, Mmarker, RegionLabel;

NS_ASSUME_NONNULL_BEGIN

/// A  label that represents a peak in fluorescence data on a view.
///
/// A peak label represents a the range in base pairs occupied by a peak in a ``Trace``.
/// The peak data is extracted from the ``Trace/peaks`` attribute of the trace.
///
/// This label occupies an rectangle that takes the whole height of the trace view. Its width is the range of the peak that the label represents.
///
/// A peak label has an ``ViewLabel/hovered`` state that is denoted by a vertical line at the peak tip. It this state, the view may show a tooltip listing basic information about the peak, depending on the value returned by ``TraceView/showPeakTooltips``.
///
/// In its ``ViewLabel/highlighted`` state, the label paints the area under the fluorescence curve at the location of the peak.
/// A peak label does not use a core animation ``ViewLabel/layer`` to draw its various states.
///
/// This class overrides the ``ViewLabel/drag`` method  to allow the user to assign an ``Allele`` to the peak that the label represents, if the peak is within the range of a marker and if the marker has bins.
@interface PeakLabel : ViewLabel

/// Returns an peak label configured with the attributes of the peak it should represents.
/// - Parameters:
///   - peak: The peak that the label will represent.
///   - view: The view on which the label will show. It must return a ``Trace`` object for its ``TraceView/trace`` property.
/// The method does not check if the `peak` is among the ``Trace/peaks`` of the trace.
- (instancetype)initWithPeak:(Peak)peak view:(TraceView *)view NS_DESIGNATED_INITIALIZER;

/// The trace of the peak that the label represents.
///
/// This is obtained from the ``TraceView/trace`` property of the label's ``ViewLabel/view`` when the label is inited.
@property (weak, nonatomic, readonly) Trace *trace;

/// The ``LadderFragment`` object (possibly an ``Allele``) at the peak that this label represents,
/// or nil if there is no such fragment at the peak.
///
/// ``ViewLabel/representedObject`` also returns this object.
@property (weak, nonatomic, readonly, nullable) LadderFragment *fragment;

/************ properties that are derived from the Peak structure *****/

/// The scan at the start of the peak (equivalent to the `startScan` member of the `Peak` struct.
@property (readonly, nonatomic) int startScan;

/// The scan at the right end of the peak that this label represents
@property (readonly, nonatomic) int endScan;

/// The scan at the tip of the peak that this label represents.
@property (readonly, nonatomic) int scan;

/// The value of the `crossTalk` member of the peak that the label represents.
@property (readonly, nonatomic) int crossTalk;

/// The position/size in base pairs corresponding to the label's ``scan``.
///
/// This value is returned by ``Trace/sizeForScan:``.
@property (readonly, nonatomic) float size;

/// The marker whose range comprises the ``size`` of the label, or nil if there is no such marker.
///
/// The marker is searched among those of the ``Chromatogram/panel`` applied to the ``Trace/chromatogram`` of the ``TraceView/trace`` that the view shows,
/// for the appropriate ``Trace/channel``.
@property (readonly, nonatomic, nullable) Mmarker *marker;

/// Makes the label draw itself.
///
/// This method is expected to be called by the hosting view during `-drawRect:`.
- (void)draw;

@end

NS_ASSUME_NONNULL_END
