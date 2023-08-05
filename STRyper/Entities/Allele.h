//
//  Allele.h
//  STRyper
//
//  Created by Jean Peccoud on 28/03/2022.
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




#import "LadderFragment.h"

@class Bin, Genotype;

NS_ASSUME_NONNULL_BEGIN

/// An entity that represents an allele of a molecular marker.
///
/// An allele defines a genetic variant of a molecular marker, or more specifically, and amplicon of such variant that induces a peak in the fluorescence data of a ``Trace``, at a specific size.
///
/// The alleles of an individual (``Chromatogram`` object) at a marker constitute a genotype (``Genotype`` object).
///
/// As opposed to a ladder fragment that can take an arbitrary ``LadderFragment/size``, this attribute should not be set independently for an allele (the ``setSize`` method should be used instead).
@interface Allele : LadderFragment

/// The genotype that the allele belongs to.
///
/// The reverse relationship is ``Genotype/alleles``.
@property (nonatomic, readonly) Genotype* genotype;

/// Inits and returns an allele added to a genotype.
///
/// The ``LadderFragment/scan`` and ``LadderFragment/size`` of the allele are set to 0.
///
/// The method returns `nil` if no trace in the ``Genotype/sample`` of the `genotype` is suitable for the allele,
/// or if the `genotype` already has enough alleles given the ``Mmarker/ploidy`` of its ``Genotype/marker``.
///
/// These conditions denotes the fact that the ``LadderFragment/trace`` and the ``genotype`` relationships of an allele should not be modified after its creation.
/// Doing so may lead to validation errors, for instance the ``Trace/channel`` of the ``LadderFragment/trace`` differing from the genotype's ``Genotype/marker``.
///
/// One should generally not call this method directly, since alleles are added by creating a ``Genotype`` object with ``Genotype/initWithMarker:sample:``, which calls this method.
/// - Parameter genotype: The genotype to which the allele will be added.
-(nullable instancetype) initWithGenotype:(Genotype *)genotype;

/// Makes the allele compute its size.
///
/// The allele computes its ``LadderFragment/size`` from its ``LadderFragment/scan``, given the sizing properties of the ``Genotype/sample`` and  ``Genotype/offset`` of its ``genotype``.
///
///	This method is called whenever the ``LadderFragment/scan`` attribute of the receiver changes.
///
///	If ``LadderFragment/scan`` returns a value that is ≤ 0, a size of 0 is set.
-(void)setSize;

/// Finds a bin comprising the allele's ``LadderFragment/size`` and names the allele after this bin.
///
///	The method searches among bins contained in the  ``genotype``'s ``Genotype/marker``.
///	If no bind is found, the "out of bin" allele name is set.
-(void)findNameFromBins;


@end


NS_ASSUME_NONNULL_END
