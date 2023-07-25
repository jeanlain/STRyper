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


/// And entity that specifies the sizes of DNA fragment composing the molecular ladder of a sample (``Chromatogram`` object).
///
/// A size standard contains a set of ``sizes`` defined in base pairs.
@interface SizeStandard : CodingObject

/// Application-related attribute that can be used to decide if the size standard can be modified in the UI.
@property (nonatomic) BOOL editable;

/// The name of the size standard.
@property (nonatomic) NSString *name;

extern NSString * const SizeStandardNameKey;

/// Sets an appropriate ``name`` to the size standard such that this name differs from the names of other size standard in the database.
///
/// The new name is based on  the existing ``name``, adding  "-copy " followed by an integer.
/// This considers that ``STRyper`` creates size standards by duplicating existing ones.
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
@property (nonatomic) NSSet<Chromatogram *> *samples;

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


