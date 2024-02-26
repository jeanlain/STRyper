//
//  Mmarker.h
//  STRyper
//
//  Created by Jean Peccoud on 13/02/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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



#import "Region.h"

@class Panel, Bin, Trace, PeakLabel, Genotype;

NS_ASSUME_NONNULL_BEGIN

/// An entity that defines the size range that alleles of the same genetic locus (molecular marker) can take.
///
///	The range of a marker is used do determine if a `Peak` detected in a trace indicates the presence of an allele at a given locus.
///	A marker also has ``bins`` that define the expected range of each allele of the locus.
///
/// Marker are organized in panels (``Panel`` objects).
///	A marker also has a ``channel`` that represents the fluorescent dye used to amplify the locus.
///
/// A marker must not overlap other markers of the same ``panel`` and ``channel``.
///
///	A marker can be copied to the paste board and accessed with in `MarkerPasteboardType` key.
///	It is copied as an archive that can be decoded with an NSKeyedUnarchiver.
///	Its ``stringRepresentation`` can also be accessed with the `NSPasteboardTypeString` key.
///
/// An "m" was added to the class name to avoid collision with a structure.
@interface Mmarker : Region <NSPasteboardWriting>

/// Inits a marker with the mandatory attributes.
///
/// The marker name is set automatically with ``Region/autoName``.
///
/// The method does not check if the parameters are valid (for instance `start` being lower than `end`).
/// - Parameters:
///   - start: The ``Region/start`` position of the marker.
///   - end: The ``Region/end`` position the marker
///   - channel: The ``channel`` of the marker
///   - panel: The ``panel`` of the marker.
-(instancetype) initWithStart:(float) start end:(float) end channel:(ChannelNumber) channel panel:(Panel *)panel;

/// The ploidy of the maker, that is, the number of expected alleles at the locus for an individual.
///
/// The default value is 2. Possible values are 1 and 2.
@property (nonatomic) int16_t ploidy;
												
/// The channel corresponding to the dye of the marker.
@property (nonatomic, readonly) ChannelNumber channel;

/// The length of the repeated motive in base pairs.
///
/// This attribute considers that alleles arise from variation in the number of short tandem repeats composing the locus.
///
/// The default value is 2. Possible values are numbers from 1 to 10.
@property (nonatomic) int16_t motiveLength;

/// The bins that the marker comprises.
///
/// The reverse relationship is ``Bin/marker``.
///
/// This relationship is encoded in ``CodingObject/encodeWithCoder:``  and decoded in ``CodingObject/initWithCoder:``.
/// It is also used to test equivalence between markers via the ``CodingObject/isEquivalentTo:`` method.
@property (nonatomic, nullable) NSSet <Bin *> *bins;

/// The genotypes that samples have for the marker.
///
///	This comprises the genotypes of all samples whose ``Chromatogram/panel`` contains the marker.
///
/// The reverse relationship is ``Genotype/marker``.
@property (nonatomic, readonly) NSSet <Genotype *> *genotypes;

/// The panel containing the marker.
///
/// The reverse relationship is ``Panel/markers``.
@property (nonatomic) Panel *panel;


/// A string representation describing the attributes of the marker.
///
/// The string is composed of the ``Region/name``, ``Region/start``, ``Region/end``, ``channel`` and ``ploidy`` attributes, separated by tabs.
@property (readonly, nonatomic) NSString *stringRepresentation;


/// Makes the receiver create new genotypes for the ``Panel/samples`` of its ``panel``.
/// - Parameter alleleName: The ``LadderFragment/name`` to give to new ``Genotype/alleles``.
///
/// This method may be used after a marker is created and expects the absence of genotypes for the receiver.
/// It would create redundant genotypes if it is not the case.
-(void)createGenotypesWithAlleleName:(NSString *)alleleName;

@end

/// A pasteboard to copy markers.
extern NSPasteboardType  _Nonnull const MarkerPasteboardType;


extern NSString * _Nonnull const MarkerBinsKey;
extern NSString * _Nonnull const MarkerPanelKey;


@interface Mmarker (CoreDataGeneratedAccessors)

-(void)addBins:(NSSet *)bins;
-(void)removeBins:(NSSet *)bins;

@end


@interface Mmarker (DynamicAccessors)

-(void)managedObjectOriginal_setPanel:(Panel *)panel;
-(void)managedObjectOriginal_setChannel:(int16_t)channel;

@end


NS_ASSUME_NONNULL_END
