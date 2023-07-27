//
//  LadderFragment.h
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
@class Trace, FragmentLabel, PeakLabel;

/// An entity that represents a DNA fragment identified in a molecular ladder.
///
///	A peak of fluorescence arise from a DNA fragment.
///	For a trace (``Trace`` object), a DNA fragment of interest can either be a fragment from the molecular ladder or the amplicon of an allele.
///
///	This class represents  the former.  Alleles are represented by objects of a subclass (``Allele`` class).
///
///	A ladder fragment or an allele has a ``scan``, which is the data point at the tip of the `Peak` that indicated its presence (see ``Trace/peaks``).
///	A ladder fragment has an expected ``size`` that is defined in the size standard applied to its sample (the ``Trace/chromatogram`` of its ``trace``).
@interface LadderFragment : CodingObject

/// The trace in which the receiver was identified.
///
/// The reverse relationship is ``Trace/fragments``.
@property (nonatomic, readonly) Trace *trace;


/// The name of the fragment.
///
/// This property is not meaningful for a ladder fragment, but it is for the ``Allele`` subclass.
@property (nonatomic) NSString *name;

/// The scan (fluorescence data point) at the tip of the peak caused by the fragment.
@property (nonatomic) int32_t scan;

/// The size of the fragment in base pairs.
@property (nonatomic) float size;

/// An estimate of the difference between the fragment's ``size`` and the size derived from its  ``scan`` and the sizing properties of its chromatogram.
///
/// This attribute is used to evaluate the accuracy of the ``size`` of the ladder fragment, hence the ``Chromatogram/sizingQuality`` parameter of a sample.
@property (nonatomic) float offset;

/// Convenience method that returns the ``size`` of the fragment, rounded to the second decimal.
///
/// For the ``Allele`` class, this returns the allele name if it is not an empty string (otherwise, its size).
@property (readonly, nonatomic) NSString *string;


@end


extern NSString * const LadderFragmentScanKey;
extern NSString * const LadderFragmentSizeKey;
extern NSString * const LadderFragmentNameKey;
extern NSString * const LadderFragmentOffsetKey;
extern NSString * const LadderFragmentStringKey;


@interface LadderFragment (DynamicAccessors)	

-(void)managedObjectOriginal_setTrace:(Trace*)trace;
-(void)managedObjectOriginal_setName:(NSString *)name;
-(void)managedObjectOriginal_setScan:(int32_t)scan;
-(void)managedObjectOriginal_setSize:(float)size;

@end
