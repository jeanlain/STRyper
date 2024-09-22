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
#import "Chromatogram.h"
@class FragmentLabel, PeakLabel;

/// An entity that represents a DNA fragment identified in a molecular ladder.
@interface LadderFragment : CodingObject

/// The trace in which the ladder fragment was identified.
///
/// The reverse relationship is ``Trace/fragments``.
/// The trace should in principle return `YES` to ``Trace/isLadder``.
@property (nonatomic, readonly) Trace *trace;


/// The name of the fragment.
///
/// This property is not meaningful for a ladder fragment, but it can be for subclasses.
@property (nonatomic, copy) NSString *name;

/// The scan (fluorescence data point) at the tip of the peak caused by the fragment.
@property (nonatomic) int32_t scan;

/// The *theoretical* size of the fragment in base pairs.
///
/// The size is that of the peak induced by the fragment, it is defined in the size standard applied to the fragment's sample (the ``Trace/chromatogram`` of its ``trace``).
/// It should typically not be a decimal number, but subclass may use decimals.
@property (nonatomic) float size;

/// An estimate of the difference between the fragment's ``size`` and the size derived from its  ``scan`` and the sizing properties of its chromatogram.
///
/// This attribute is used to evaluate the accuracy of the ``size`` of the ladder fragment, hence the ``Chromatogram/sizingQuality`` parameter of a sample.
@property (nonatomic) float offset;

/// Convenience method that returns the ``size`` of the fragment, rounded to the second decimal.
@property (readonly, nonatomic) NSString *string;


/// Whether the fragment represents an additional peak.
///
/// Objects of this class return `NO`. 
@property (nonatomic, readonly) BOOL additional;


@end


extern CodingObjectKey LadderFragmentScanKey,
LadderFragmentSizeKey,
LadderFragmentNameKey,
LadderFragmentOffsetKey,
LadderFragmentStringKey;


@interface LadderFragment (DynamicAccessors)	

-(void)managedObjectOriginal_setTrace:(Trace*)trace;
-(void)managedObjectOriginal_setName:(NSString *)name;
-(void)managedObjectOriginal_setScan:(int32_t)scan;
-(void)managedObjectOriginal_setSize:(float)size;

@end
