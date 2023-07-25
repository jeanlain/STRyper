//
//  SizeStandardSize.h
//  STRyper
//
//  Created by Jean Peccoud on 21/12/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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



#import "CodingObject.h"

@class SizeStandard;


/// An entity that represents a particular size of a size standard (``SizeStandard`` object).
@interface SizeStandardSize : CodingObject
/// We could have just used and NSData attribute on ``SizeStandard`` to store all sizes, but this entity simplifies the edition of a size standard via a tableview.

/// the size of the receiver, in base pairs.
@property (nonatomic) int16_t size;

/// The size standard to which the receiver belongs.
///
/// The reverse relationship is ``SizeStandard/sizes``.
@property (nonatomic) SizeStandard *sizeStandard;

/// Gives a valid ``size`` to the receiver that avoids duplicates with other sizes in the ``sizeStandard``.
///
/// The initial size used is that of the receiver and is at least 20.
-(void)autoSize;

@end
