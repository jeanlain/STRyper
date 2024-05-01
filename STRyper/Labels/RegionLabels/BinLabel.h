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

NS_ASSUME_NONNULL_BEGIN

/// A label that represents a bin on a ``TraceView``.
///
/// A bin label is not ``ViewLabel/enabled`` by default and does not react to a change in ``RegionLabel/editState``, as it can only modify its own ``RegionLabel/region``.
///
/// The ``Region/name`` of its bin only shows if the label is wide enough.
@interface BinLabel : RegionLabel

/// Makes the label remove the bin from its ``Bin/marker``, regardless of the `sender`.
- (void)deleteAction:(id)sender;

/// The rectangle where the bin name shows, in view coordinates.
///
/// This rectangle can be wider then the bin's ``ViewLabel/frame`` and is never narrower. 
/// This property can be used to avoid overlap between names of adjacent bin labels, in conjunction to ``binNameHidden``.
@property (nonatomic, readonly) NSRect binNameRect;

/// Whether the bin name is hidden.
///
/// The bin name is always hidden of the label is itself is hidden.
@property (nonatomic) BOOL binNameHidden;

/// Used internally to access the labels CA layer.
@property (nonatomic, readonly) CALayer *_layer;

@end

NS_ASSUME_NONNULL_END
