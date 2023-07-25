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
/// A TraceView marker label shows the range of a marker (``Mmarker`` object)  on a ``TraceView`` and allows the user to edit bins, move bins and modify the maker offset of target samples.
///
/// This label is ``ViewLabel/hidden`` when it is not ``ViewLabel/enabled``.
///
/// Its ``RegionLabel/binLabels`` property returns labels for the ``Mmarker/bins`` of its marker.
///
/// When its ``RegionLabel/editState``  is `editStateNil` (which is the default), the label is not ``ViewLabel/enabled``.
///
/// When its state is `editStateBinSet`, the label is ``ViewLabel/highlighted`` and can be used to resize and move its ``RegionLabel/binLabels`` with its ``ViewLabel/drag`` method.
///
/// When its state is `editStateBinSet`, the label is ``ViewLabel/enabled``, so are its ``RegionLabel/binLabels``, to allows the user to add and modify bins manually.
/// The label cannot be ``ViewLabel/highlighted`` when it is in this state.
///
/// When the label is in another ``RegionLabel/editState``, it is ``ViewLabel/highlighted``  and can be used to edit the marker offset of target samples, with its ``ViewLabel/drag`` method.
///
/// The ``ViewLabel/cancelOperation:`` message sets the ``RegionLabel/editState`` of the label to `editStateNil`.
///
/// The ``ViewLabel/mouseDownInView`` message has the same effect if the ``ViewLabel/view``'s ``LabelView/clickedPoint`` lies outside the label's ``ViewLabel/frame``.
@interface TraceViewMarkerLabel : RegionLabel 



@end

NS_ASSUME_NONNULL_END
