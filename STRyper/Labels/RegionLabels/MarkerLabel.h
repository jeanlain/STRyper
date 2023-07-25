//
//  MarkerLabel.h
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

/// A label that represents a molecular marker on a ``MarkerView``.
///
/// A marker label shows the range of a molecular marker on a ``MarkerView`` and allows the user to rename the marker and to resize it by dragging an edge.
///
/// The resizing behaviour is implemented in the ``ViewLabel/drag`` method.
///
/// When it is ``ViewLabel/hovered`` or ``ViewLabel/highlighted``, the label shows a button that pops the label's ``ViewLabel/menu``.
/// This  menu allowing several actions described in the ``STRyper`` user guide.
///
/// To implement some of these actions, the label must find an label representing its marker among the ``LabelView/markerLabels`` of its marker view's ``MarkerView/traceView``.
@interface MarkerLabel : RegionLabel <NSMenuDelegate>


@end

NS_ASSUME_NONNULL_END
