//
//  SizeStandard.h
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
@class SizeStandardSize, Chromatogram, PeakLabel;

NS_ASSUME_NONNULL_BEGIN

/// And entity that specifies the sizes of DNA fragment composing the molecular ladder of a sample (``Chromatogram`` object).
///
/// A size standard contains a set of ``sizes`` defined in base pairs.
/// Its ``sizeSample:`` class method can be used to find ladder fragments in a chromatogram that has a ``Chromatogram/sizeStandard``
/// applied to it, and to compute sizing parameters based on these fragments.
@interface SizeStandard : CodingObject

/// Application-related attribute that can be used to decide if the size standard can be modified in the UI.
@property (nonatomic) BOOL editable;

/// The name of the size standard.
@property (nonatomic, copy) NSString *name;

extern CodingObjectKey SizeStandardNameKey;

/// Sets an appropriate ``name`` to the size standard such that this name differs from the names of other size standard in the database.
///
/// The new name is based on  the existing ``name``, adding  "-copy " followed by an integer.
/// This considers that `STRyper` creates size standards by duplicating existing ones.
- (void)autoName;

/// The sizes that the size standard defines.
///
/// This reverse relationship is ``SizeStandardSize/sizeStandard``.
///
/// This relationship is encoded in ``CodingObject/encodeWithCoder:``  and decoded in ``CodingObject/initWithCoder:``.
@property (nonatomic) NSSet<SizeStandardSize *> *sizes;

/// The samples that use the size standard for sizing.
///
/// The reverse relationship is ``Chromatogram/sizeStandard``.
@property (nonatomic, nullable) NSSet<Chromatogram *> *samples;

/// Finds ladder fragments in a  chromatogram, based in the size standard applied to it, and computes sizing properties.
///
/// This method finds peaks that correspond to the ``SizeStandard/sizes`` of the ``Chromatogram/sizeStandard``,
/// sets the trace's `fragments` accordingly and calls ``Chromatogram/computeFitting``.
///
/// This method does nothing if there is no ``Chromatogram/ladderTrace`` or if `sample` has no size standard.
/// - Parameter sample: A chromatogram.
+ (void) sizeSample:(Chromatogram *)sample;

/// Computes the regression between between two variables, using ordinary least squares.
///
/// - Parameters:
///   - x: The values for the first variable.
///   - y: The values for the second variable.
///   - nPoints: The number of values to consider for `x` and `y`.
///   - slope: On output, will contain the slope parameter of the regression.
///   - intercept: On output, will contain the intercept parameter of the regression.
void regression (float *x, float *y, NSInteger nPoints, float *slope, float *intercept);


@end


NS_ASSUME_NONNULL_END
