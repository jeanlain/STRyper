//
//  TraceViewMarkerLabel.h
//  STRyper
//
//  Created by Jean Peccoud on 25/03/2023.
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


#import "RegionLabel.h"

NS_ASSUME_NONNULL_BEGIN

/// A label that represents a molecular marker on a ``TraceView``.
///
/// A TraceView marker label shows the range of a marker (``Mmarker`` object)  on a ``TraceView`` and allows the user to edit bins, 
/// move bins and modify the maker offset of target samples.
///
/// A TraceView marker label automatically creates/updates bin labels for the marker it represents.
/// It repositions bin labels in its ``ViewLabel/reposition`` method, avoiding overlap in bin names,
/// and updates their tracking areas in its ``ViewLabel/updateTrackingArea`` method.
@interface TraceViewMarkerLabel : RegionLabel

/// Implements ``ViewLabel/mouseDownInView``.
///
///  if the ``ViewLabel/view``'s ``LabelView/clickedPoint`` lies outside the label's ``ViewLabel/frame``,
///  the method sets the ``RegionLabel/editState`` of the label to `editStateNil`.
- (void)mouseDownInView;

/// Sets the label's ``RegionLabel/editState``.
///
/// When set to `editStateNil` (the initial state), the label is not ``ViewLabel/enabled``.
///
/// When set to `editStateBins`, the label gets ``ViewLabel/enabled``, so do all its ``RegionLabel/binLabels``.
/// The label cannot be ``ViewLabel/highlighted`` when it is in this state.
///
/// When set to another value , the label is ``ViewLabel/highlighted`` and its bin labels are disabled.
- (void)setEditState:(EditState)editState;

/// Implement the ``ViewLabel/drag`` method.
///
/// The method moves or resizes the label to move/resize its set of ``RegionLabel/binLabels`` if the label's ``RegionLabel/editState`` is `editStateBinSet`,
/// or to edit the ``Genotype/offset`` of target genotypes if its `editState` is `editStateOffset`.
///
/// The method prevents excessive resizing and constrains bins within their ``Bin/marker``'s range.
/// See ``STRyper``'s user guide for a visual representation.
- (void)drag;

/// Used internally to access the label's CA layer by the bin labels.
@property (nonatomic, readonly) CALayer *_layer;

@end

NS_ASSUME_NONNULL_END
