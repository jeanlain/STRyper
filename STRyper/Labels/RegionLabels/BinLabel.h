//
//  BinLabel.h
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
@class Bin;

NS_ASSUME_NONNULL_BEGIN

/// A label that represents a bin on a ``TraceView``.
///
/// A bin label shows the range of a ``Bin`` on a ``TraceView`` and allows the user to rename the bin and to move/resize it by dragging.
///
/// The resizing/dragging behaviour is implemented in the ``ViewLabel/drag`` method.
/// The ``ViewLabel/deleteAction:`` messaged make the label remove the bin from its ``Bin/marker``.
///
/// A bin label is not ``ViewLabel/enabled`` by default.
///
/// This label does not react to a change in ``RegionLabel/editState``, as it can only modify its own ``RegionLabel/region``.
///
/// The ``Region/name`` of its bin only shows if the label is wide enough.
@interface BinLabel : RegionLabel


@end

NS_ASSUME_NONNULL_END
