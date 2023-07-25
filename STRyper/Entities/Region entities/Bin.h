//
//  Bin.h
//  STRyper
//
//  Created by Jean Peccoud on 07/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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




#import "Region.h"

@class Mmarker;

NS_ASSUME_NONNULL_BEGIN

/// An entity that defines the size range that an allele may have.
///
///	A bin is principally used during allele calling, to name alleles whose size fall within its range.
///
///	A bin is associated with a ``marker``. The set of bins of the marker represent the possible alleles that exist for the corresponding locus.
@interface Bin : Region

/// The marker to which the bin belongs.
///
/// The reverse relationship is ``Mmarker/bins``.
@property (nonatomic, readonly) Mmarker *marker;

/// Inits a bin with the mandatory attributes.
///
/// The bin name is set automatically with ``Region/autoName``.
///
/// This method returns `nil` if the start and end parameters are inconsistent (negative, too large, or `start` ≥  `end`),
/// if the `channel` value is invalid, but it does not check if the  overlaps with other markers of the `panel`.
/// - Parameters:
///   - start: The ``Region/start`` position of the bin.
///   - end: The ``Region/end`` position the bin.
///   - marker: The ``marker`` of the bin.
-(instancetype) initWithStart:(float) start end:(float) end marker:(Mmarker *)marker;

/// A string representation describing the attributes of the receiver.
///
/// The string is composed of the ``Region/name``, ``Region/start`` and ``Region/end`` attributes, separated by tabs.
-(NSString *)stringRepresentation;

@end


@interface Bin (DynamicAccessors)
/// the marker of a bin should not be changed by other objects after its creation, except during folder import from an archive if the imported panel may be replaced.
-(void)managedObjectOriginal_setMarker:(nullable Mmarker *)marker;

@end



NS_ASSUME_NONNULL_END
