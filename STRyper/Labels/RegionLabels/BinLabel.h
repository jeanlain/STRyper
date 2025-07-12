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
@class TraceViewMarkerLabel;

NS_ASSUME_NONNULL_BEGIN

/// A label that represents a bin on a ``TraceView``.
///
/// A bin label is not ``ViewLabel/enabled`` by default and does not react to a change in ``RegionLabel/editState``, as it can only modify its own ``RegionLabel/region``.
///
///	As a bin is part of a set belonging to a ``Bin/marker``, a bin label does not need to be created and added to a view, nor positioned individually.
///	Bin labels are created, managed and positioned by the ``TraceViewMarkerLabel`` object that represents their marker.
///	They take their ``RegionLabel/offset`` from this "parent" label.
@interface BinLabel : RegionLabel

/// Makes the label remove the bin from its ``Bin/marker``, regardless of the `sender`.
- (void)deleteAction:(id)sender;


/// Rearranges bin labels on their host view, and avoids overlaps in bin names by hiding them if necessary.
///
/// - Parameters:
///   - binLabels: The bin labels to rearrange. They are assumed to be hosted by the same view and ordered from left to right in the array.
///   - reposition: whether bin labels should be repositioned. If `NO`, only the visibility of bin names is managed.
+ (void)arrangeLabels:(NSArray<BinLabel *> *)binLabels withRepositioning:(BOOL)reposition;

/// The label that represents the marker containing the bin represented by the label.
///
/// This property is set internally.
@property (nonatomic, weak) TraceViewMarkerLabel *parentLabel;

- (void)_shiftByOffset:(MarkerOffset)offset;

@end

NS_ASSUME_NONNULL_END
