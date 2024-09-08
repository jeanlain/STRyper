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
/// A peak label is invisible even if ``ViewLabel/highlighted`` (its host view draws the peak), 
/// but its ``ViewLabel/frame`` takes the whole height of the trace view.
/// Its width is the range of the peak that the label represents.
///
/// A peak label does not have a ``ViewLabel/representedObject`` but shows in a tooltip containing its ``description`` 
/// when the label is ``ViewLabel/hovered`` and if its view returns `YES` to ``TraceView/showPeakTooltips``.
@interface PeakLabel : ViewLabel

/// Returns an peak label configured with the attributes of the peak it should represents.
/// - Parameters:
///   - peak: The peak that the label will represent.
///   - view: The view on which the label will show. It must return a ``Trace`` object for its ``TraceView/trace`` property.
/// The method assumes that the `peak` is among the ``Trace/peaks`` of the trace.
- (instancetype)initWithPeak:(Peak)peak view:(nullable TraceView *)view NS_DESIGNATED_INITIALIZER;


/// The ``LadderFragment`` object (possibly an ``Allele``) at the peak that the label represents,
/// or `nil` if there is no such fragment at the peak.
///
/// ``ViewLabel/representedObject`` also returns this object.
@property (weak, nonatomic, readonly, nullable) __kindof LadderFragment *fragment;

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


/// Set the label's properties to that of a peak.
///
/// The method assumes that the `peak` is among the ``Trace/peaks`` of the ``TraceView/trace`` that the ``ViewLabel/view`` shows.
/// - Parameter peak: The peak that the label will represent.
- (void)setPeak:(Peak)peak;


/// The marker whose range comprises the ``size`` of the label, or `nil` if there is no such marker.
///
/// The marker is searched among those of the ``Chromatogram/panel`` applied to the ``Trace/chromatogram`` of the ``TraceView/trace`` that the view shows,
/// for the appropriate ``Trace/channel``.
@property (weak, readonly, nonatomic, nullable) Mmarker *marker;

/// Removes the tooltip rectangle used by the label, if any.
- (void)removeTooltip;


/****************notable implementations of methods defined in superclasses *****************/

/// Calls ``ViewLabel/reposition`` on the receiver, then ``ViewLabel/updateTrackingArea`` on `super`.
///
/// Because a peak label that is not dragged affects the UI only through its ``ViewLabel/trackingArea``,
/// it need repositioning only when its tracking area is updated.
-(void)updateTrackingArea;

/// A description of the represented peak: its ``size``, height in RFU, ``scan`` and whether it results from ``crossTalk``.
- (NSString *)description;

/// Implements the ``ViewLabel/drag`` method.
///
/// If the label is within a range of a ``Mmarker`` and its view shows ``BinLabel`` objects, 
/// the method draws a handle starting at the horizontal position of the peak tip and ending a the mouse location.
/// When the mouse reaches a bin label, the label takes its ``ViewLabel/hovered`` state.
///
/// At the end of dragging, the peak will take a ``FragmentLabel`` representing a allele named after the bin.
///
/// See ``STRyper`` documentation for an illustration.
- (void)drag;

/// A menu allowing to remove an allele or ladder fragment at the peak location, or to add a additional peak (additional ``Allele``) 
/// if the peak is in a marker range and has no allele at is location.
- (nullable NSMenu *)menu;

/// Implements the ``ViewLabel/doubleClickAction:`` method.
///
/// The method allows the user to assign/detach an allele to the peak at the label. 
/// See ``STRyper`` used guide for more information.
- (void)doubleClickAction:(id)sender;

@end

NS_ASSUME_NONNULL_END
