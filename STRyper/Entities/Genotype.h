//
//  Genotype.h
//  STRyper
//
//  Created by Jean Peccoud on 02/04/2022.
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



#import "CodingObject.h"
#import "Trace.h"
@class Mmarker, Chromatogram, Allele;



NS_ASSUME_NONNULL_BEGIN


/// An entity that describes the genotype of a sample at a molecular marker.
///
/// A genotype regroups the ``alleles`` of a ``sample`` (chromatogram) at a molecular ``marker``.
/// The alleles may comprise additional fragments which have caused peaks in the marker range.
/// A new genotype comes with "blank" alleles that have a ``LadderFragment/scan`` of 0 and no ``LadderFragment/name``.
///
/// The ``callAllelesAndAdditionalPeak:`` method can be used to identify the genotype's ``alleles`` in terms of size and name, given the ``FluoTrace/peaks``  found in its sample's trace in the range of its marker.
@interface Genotype : CodingObject <NSPasteboardWriting>;


/// Inits an returns a genotype for a sample and a marker, giving it the necessary alleles.
///
/// The alleles added to the genotype are created with ``Allele/initWithGenotype:additional:``.
///
/// This method returns `nil` if the `sample` and `marker` do not have the same managed object context, if the sample's ``Chromatogram/panel`` doesn't contain the `marker`, if  the `sample` already has a genotype for the `marker`,
/// of if `sample` contains no valid ``Chromatogram/traces`` for the ``Mmarker/channel`` of the `marker`.
- (nullable instancetype)initWithMarker:(Mmarker *)marker sample:(Chromatogram *)sample;


/// The sample that contains the genotype.
///
/// The reverse relationship is ``Chromatogram/genotypes``.
@property (nonatomic, readonly) Chromatogram *sample;

/// The marker of the genotype.
///
/// The reverse relationship is ``Mmarker/genotypes``.
@property (nonatomic, readonly) Mmarker *marker;


#pragma mark - properties and methods related to alleles


/// The alleles and additional fragments of the genotype.
///
/// The reverse relationship is ``Allele/genotype``.
@property (nonatomic, readonly, nullable) NSSet<Allele *> *alleles;
/// The name "alleles" was chosen in the model before additional fragments were implemented, and can be a bit misleading

/// The "assigned" (non additional) alleles composing the genotype.
///
/// The number of alleles must be the same as the ``Mmarker/ploidy`` of the genotype's ``marker``.
@property (nonatomic, readonly, nullable) NSSet<Allele *> *assignedAlleles;


/// The fragments (putative alleles) that may have cause additional peak at the marker.
///
/// This relationship can be used to indicate the presence of DNA contamination, paralogs of the marker
/// or polyploidy.
@property (nonatomic, readonly, nullable) NSSet<Allele *> *additionalFragments;

/// A string describing the ``alleles``.
///
/// For additional fragments sorted by increasing size, the string include the size, the name (separated by a colon).
/// Spaces separate fragments.
@property (nonatomic, readonly, nullable) NSString *additionalFragmentString;


/// Makes the genotype characterize its ``alleles``  optionally containing "additional" ones.
///
/// This method looks for peaks in the range of the genotype's ``marker`` in the trace whose ``FluoTrace/channel`` corresponds to the channel of the marker.
/// It gives each allele the ``LadderFragment/scan`` of a suitable peak, and calls ``Allele/findNameFromBins``.
/// 
/// If no suitable peak is found, any assigned allele is given a scan of 0.
/// - Parameter annotateSuppPeaks: Whether additional peaks should be annotated, creating ``additionalFragments``.
- (void)callAllelesAndAdditionalPeak:(BOOL)annotateSuppPeaks;

/// Makes the genotype name its ``alleles`` based on the bins of its marker.
///
/// The method calls ``Allele/findNameFromBins``.
- (void)binAlleles;

/// The allele of shorter size for a diploid genotype, or the only allele.
@property (nonatomic, readonly, nullable) Allele *allele1;

/// The longer allele for a diploid genotype, or `nil` for a haploid.
@property (nonatomic, readonly, nullable) Allele *allele2;

/// The maximum height ratio (in RFU) measured between peaks that represent adenylation and alleles, for peaks that are at the right of alleles.
///
/// This property is zero if ``callAllelesAndAdditionalPeak:`` was not called after the genotype was inserted/fetched.
@property (readonly) float leftAdenylationRatio;

/// The maximum height ratio (in RFU) measured between peaks that represent adenylation  and alleles, for peaks that are at the left of alleles.
///
/// This property is zero if ``callAllelesAndAdditionalPeak:`` was not called after the genotype was inserted/fetched.
@property (readonly) float rightAdenylationRatio;

/// The scan of a peak that could represent and allele.
///
/// This property is zero if ``callAllelesAndAdditionalPeak:`` was not called after the genotype was inserted/fetched.
@property (readonly) int scanOfPossibleAllele;

/// Whether the genotype is heterozygous, i.e., whether the positions (scans) of its ``assignedAlleles`` differ (and differ from zero).
@property (readonly) BOOL heterozygous;


#pragma mark - genotype status

/// An integer that denotes the status of a genotype and that can be used to notify the user that its alleles should be checked.
typedef NS_ENUM(int32_t, GenotypeStatus) {
	/// Denotes that the alleles have not been called nor edited, hence they have no size and no name.
	genotypeStatusNotCalled,
	
	/// Denotes that not peak has been detected in allele call.
	genotypeStatusNoPeak,
	
	/// Denotes that alleles have been called automatically (and found) using the `callAllelesAndAdditionalPeak` method.
	genotypeStatusAutomatic,
	
	/// Denotes that the sample sizing has changed.
	genotypeStatusSizingChanged,
	
	/// Denote that the offset or marker of the genotype has been edited (bins included) after the genotype was called/edited.
	genotypeStatusMarkerChanged,
	
	/// The genotype was edited manually by the user.
	genotypeStatusManual,
	
	/// The sample has not proper sizing, no genotype should not be used.
	genotypeStatusNoSizing
} ;

/// The status of the genotype.
///
/// The default value is `genotypeStatusNotCalled`.
@property (nonatomic) GenotypeStatus status;

/// A text that explains the genotype's ``status``.
///
/// This text can be used to show in a UI element.
@property (nonatomic, readonly, nullable) NSString *statusText;

/// Text notes that can be added to the genotype.
///
/// This property can be used to store a description of manual changes made the genotype.
@property (nonatomic, copy) NSString *notes;

		
#pragma mark - marker offset

/// A structure that defines the offset that alleles sizes of a genotype may have, compared to references sizes.
///
/// A marker offset addresses the fact that the same allele may migrate differently (hence appear at different sizes) between sequencing runs.
///
/// This offset can be used to multiply an allele size by the `slope` and adding the `intercept`  member.
/// This results in a new size that may match the size obtained in reference runs.
///
/// See ``STRyper`` user guide for more explanations.
typedef struct MarkerOffset {
	
	/// The intercept of the offset.
	float intercept;
	
	/// The slope of the offset.
	float slope;
} MarkerOffset;


/// Returns a marker offset with the specified members.
MarkerOffset MakeMarkerOffset(float intercept, float slope);

/// Specifies a marker offset that has no effect (intercept of 0.0 and slope of 1.0)
extern const MarkerOffset MarkerOffsetNone;

/// The marker offset of the genotype.
///
/// The `MarkerOffset` struct is placed in an `NSData` object for compatibility with core data.
@property (nonatomic, nullable) NSData *offsetData;

/// The marker offset derived from the ``offsetData`` attribute.
///
/// If ``offsetData`` returns `nil`, the method returns `MarkerOffsetNone`.
@property (nonatomic, readonly) MarkerOffset offset;

///A string representing the genotype's ``offset`` in the format : '(`intercept`, `slope`)', which can be used in the UI.
@property (nonatomic, nullable, readonly) NSString *offsetString;

/// The `intercept` of the ``offset``.
@property (nonatomic, readonly) float offsetIntercept;

/// The `slope` of the ``offset``.
@property (nonatomic, readonly) float offsetSlope;

#pragma mark - display properties

/// The maximum fluorescence level that can be set by a view displaying the genotype.
///
/// A genotype is likely to be displayed in a row of a table. As `NSTableView` objects shuffle and reuse views for rows and cells,
/// a trace may be randomly shown in different views (``TraceView`` objects)..
///
/// A ``TraceView`` can use this property to set  its ``TraceView/topFluoLevel``.
@property (nonatomic) float topFluoLevel;

/// The range of the genotype's ``marker`` when accounting for its offset.
@property (nonatomic, readonly) BaseRange range;

@end


@interface Genotype (DynamicAccessors)
/// The marker of a genotype should not be changed by other objects after its creation, except during folder import from an archive, if the imported panel is replaced
-(void)managedObjectOriginal_setMarker:(nullable Mmarker *)marker;

/// Alleles should in principle not be changed after a genotype is created, but in the case of a Chromatogram copy, we have to
-(void)managedObjectOriginal_setAlleles:(nullable NSSet *)alleles;

-(void)managedObjectOriginal_setStatus:(int32_t)status; /// Used internally, but we may as well leave this here since we have this extension in the header.
-(void)managedObjectOriginal_setOffsetData:(nullable NSData *)offsetData;

/// The sample of a genotype should not be changed by other objects after its creation, except during copy or import.
-(void)managedObjectOriginal_setSample:(nullable Chromatogram *)sample;


@end



NS_ASSUME_NONNULL_END
