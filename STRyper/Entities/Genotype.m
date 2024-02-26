//
//  Genotype.m
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



#import "Genotype.h"
#import "Mmarker.h"
#import "Chromatogram.h"
#import "PeakLabel.h"
#import "Allele.h"
#import "Panel.h"
@import Accelerate;

NSNotificationName _Nonnull const GenotypeDidChangeOffsetCoefsNotification = @"GenotypeDidChangeOffsetCoefsNotification";
static void * const offsetChangedContext = (void*)&offsetChangedContext;

/// Predicates used to fetch alleles that are assigned or additional.
static NSPredicate *assignedAllelePredicate;
static NSPredicate *additionalFragmentPredicate;

@interface Genotype ()

@property (nullable, nonatomic) NSSet<Allele *> *assignedAlleles;
@property (nullable, nonatomic) NSSet<Allele *> *additionalFragments;

/// Properties which helps displaying the genotype in the UI
@property (nullable, nonatomic) Allele *allele1;
@property (nullable, nonatomic) Allele *allele2;
@property (nullable, nonatomic) NSArray<Allele *> *sortedAlleles;
@property (nullable, nonatomic) NSArray<Allele *> *sortedAdditionalFragments;
@property (nullable, nonatomic) NSString *additionalFragmentString;

@end


@implementation Genotype


@dynamic alleles, marker, sample, status, notes, offsetData;

@synthesize topFluoLevel = _topFluoLevel, assignedAlleles = _assignedAlleles, 
allele1 = _allele1, allele2 = _allele2, additionalFragmentString = _additionalFragmentString,
additionalFragments = _additionalFragments, sortedAlleles = _sortedAlleles,
sortedAdditionalFragments = _sortedAdditionalFragments;


/// global variable use by all instances
static NSArray<NSString *> *statusTexts;		/// the text for the different statuses
	

+ (void)initialize {
	
	
	statusTexts = @[@"Genotype not called",
					@"No peak detected",
					@"Genotype called",
					@"Sample sizing has changed!",
					@"Marker has been edited",
					@"Genotype edited manually"];
	
	assignedAllelePredicate = [NSPredicate predicateWithBlock:^BOOL(Allele * allele, NSDictionary<NSString *,id> * _Nullable bindings) {
		return allele.additional == NO;
	}];
	
	additionalFragmentPredicate = [NSPredicate predicateWithBlock:^BOOL(Allele * allele, NSDictionary<NSString *,id> * _Nullable bindings) {
		return allele.additional;
	}];
}


- (nullable instancetype)initWithMarker:(Mmarker *)marker sample:(Chromatogram *)sample {
	if(sample.managedObjectContext == nil || sample.managedObjectContext != marker.managedObjectContext) {
		return nil;
	}
	if(![sample.panel.markers containsObject:marker]) {
		return nil;
	}
	for(Genotype *genotype in sample.genotypes) {
		if(genotype.marker == marker) {
			return nil;
		}
	}
	
	Trace *trace = [sample traceForChannel:marker.channel];
	if(!trace || trace.isLadder) {
		return nil;
	}
	
	self = [super initWithContext:marker.managedObjectContext];
	if(self) {
		[self managedObjectOriginal_setMarker:marker];
		[self managedObjectOriginal_setSample:sample];
		for (int i = 1; i <= marker.ploidy; i++) {
			Allele *newAllele = [[Allele alloc] initWithGenotype:self additional:NO];
			if(!newAllele) {
				NSLog(@"%@", [NSString stringWithFormat:@"failed to add allele for marker %@ and sample %@", marker.name, sample.sampleName]);
			}
		}
	}
	return self;
}


- (void)awakeFromFetch {
	[super awakeFromFetch];
	/// We need to react when our alleles change (content or size).
	NSManagedObjectContext *MOC = self.managedObjectContext;
	if(MOC) {
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(contextDidChange:)
												   name:NSManagedObjectContextObjectsDidChangeNotification
												 object:MOC];
		
		[self addObserver:self forKeyPath:@"offsetData" options:NSKeyValueObservingOptionNew context:offsetChangedContext];

	}

}


- (void)awakeFromInsert {
	[super awakeFromInsert];
	[self addObserver:self forKeyPath:@"offsetData" options:NSKeyValueObservingOptionNew context:offsetChangedContext];
	
	NSManagedObjectContext *MOC = self.managedObjectContext;
	if(MOC) {
		[NSNotificationCenter.defaultCenter addObserver:self 
											   selector:@selector(contextDidChange:)
												   name:NSManagedObjectContextObjectsDidChangeNotification
												 object:MOC];
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == offsetChangedContext) {
		[NSNotificationCenter.defaultCenter postNotificationName:GenotypeDidChangeOffsetCoefsNotification object:self];
	} else [self observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - allele calling and genotype status

/// A structure for allele calling, which describe a peak found in a marker range
typedef  struct MarkerPeak {
	int32_t scan;					/// the scan corresponding to the peak tip
	float height;					/// its height in RFU
	float size;						/// the size in base pairs that corresponds to the scan
	int32_t crossTalk;				/// see equivalent property in Peak struct (not currently used, as we ignore crosstalk peaks)
	
	/// The following members consider that microsat alleles yield clusters of peaks due to stuttering and adenylation.
	/// A peak can be considered as the "parent" peak of the cluster, the one that will be considered as representing the allele
	/// and it would have "children" peaks that supposedly arise from the same allele
	int16_t nChildPeaks;			/// Number of child peaks (in principle, the peak would have no parent)
	int16_t parentPeak;				/// For a child peak, this is the index of the parent peak (-1 is the peak is no parent)
	float stutterRatio;				/// The ratio in height between the peak and its neighbor that is closer to the parent peak in the cluster
									/// We expect this ratio to be less than 1, as stuttering gradually decreases

} MarkerPeak;


MarkerPeak MarkerPeakFromPeak(Peak peak, const int16_t *fluo, const float *sizes, MarkerOffset offset) {
	MarkerPeak markerPeak;
	int scan = peak.startScan + peak.scansToTip;
	markerPeak.scan = scan;
	markerPeak.height = fluo[scan];
	markerPeak.crossTalk = peak.crossTalk;
	markerPeak.size = (sizes[scan] - offset.intercept)/offset.slope;
	markerPeak.stutterRatio = 0;
	markerPeak.nChildPeaks = 0;
	markerPeak.parentPeak = -1;
	return markerPeak;
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingStatusText {
	return [NSSet setWithObject:@"status"];
}


- (void)setStatus:(GenotypeStatus)status {
	if(status != self.status) {
		if(self.status <= genotypeStatusNotCalled &&			/// when the genotype is not called, it cannot take certain statuses
		   (status == genotypeStatusMarkerChanged || status == genotypeStatusSizingChanged)) {
			return;
		}
		[self managedObjectOriginal_setStatus:status];
	}
}



- (nullable NSString *)statusText {
	if(self.status < statusTexts.count) {
		return statusTexts[self.status];
	}
	return nil;
}


- (void)callAllelesAndSupplementaryPeak:(BOOL)annotateSuppPeaks {
	Chromatogram *sample = self.sample;
	if(sample.sizingQuality.floatValue <= 0) {
		/// we don't call alleles for a samples that is not sized
		return;
	}
	
	Mmarker *marker = self.marker;
	Trace *trace = [sample traceForChannel:marker.channel];
	if(!trace || !marker) {
		return;
	}
	
	NSData *peakData = trace.peaks;
	long totPeaks = peakData.length/sizeof(Peak);
	if(totPeaks == 0) {
		for(Allele *allele in self.alleles) {
			if(!allele.additional) {
				allele.scan = 0;
			} else {
				[allele removeFromGenotypeAndDelete];
			}
		}
		self.status = genotypeStatusNoPeak;
		return;
	}
	
	/// we define the range of sizes to select peaks that could be alleles
	float startSize = self.marker.start;
	float endSize = self.marker.end;
	
	/// we access the fluo levels of the trace
	NSData *rawData = trace.rawData;
	const int16_t *fluo = rawData.bytes;
	long nScans = rawData.length/sizeof(int16_t);
	
	/// we select peaks in the range. We will first store their height and their indices as we will examine them by decreasing height
	int *peakIndices = malloc(totPeaks * sizeof(int));	/// The position of peak structs in the peaks attribute of the trace
	float *heights = malloc(totPeaks * sizeof(float));	/// The heights of peaks

	int nPeaks = 0;										/// the number of peaks in the range
	vDSP_Length *markerPeakIndices = malloc(totPeaks * sizeof(vDSP_Length));	/// will be 0..nPeaks
	const Peak *peaks = peakData.bytes;
	for(int i = 0; i < totPeaks; i++) {
		Peak peak = peaks[i];
		int scan = peak.startScan + peak.scansToTip;
		float size = [sample sizeForScan:scan];
		if(size > endSize || scan + peak.scansFromTip >= nScans) {
			break;
		} else if(size >= startSize && peak.crossTalk >= 0) {		/// we ignore peaks due to crosstalk
			peakIndices[nPeaks] = i;
			markerPeakIndices[nPeaks] = nPeaks;
			heights[nPeaks] = fluo[scan] + peak.crossTalk * 10e5;	/// as an estimate of height, we actually use the with of the saturated region (if positive) as a first criterion. Then the actual raw fluorescence level, is used as a second criterion
			nPeaks++;
		}
	}
	
	if(nPeaks == 0) {
		free(peakIndices);
		free(heights);
		free(markerPeakIndices);
		for(Allele *allele in self.alleles) {
			if(!allele.additional) {
				allele.scan = 0;
			} else {
				[allele removeFromGenotypeAndDelete];
			}
		}
		self.status = genotypeStatusNoPeak;
		return;
	}
	
	/// from now on, the genotype is considered called
	self.status = genotypeStatusAutomatic;
	
	/// to contain the peaks to inspect
	MarkerPeak markerPeaks[nPeaks];
	
	MarkerOffset offset = self.offset;
	NSData *sizeData = sample.sizes;
	const float *sizes = sizeData.bytes;
	for(int i = 0; i < nPeaks; i++) {
		int index = peakIndices[i];
		markerPeaks[i] = MarkerPeakFromPeak(peaks[index], fluo, sizes, offset);
	}
	
	/// as we will inspect the peak by decreasing height, we sort the peak indices according to this criterion
	/// We sort the indices, not the peak themselves, as we also need to the peak to be sorted by size (in base pairs), to examine their neighbor
	vDSP_vsorti(heights, markerPeakIndices, NULL, nPeaks, -1);

	free(heights);

	free(peakIndices);
	
	float rightMaxDropOut = 0.3;		/// The minimum ratio of height to consider an allele that is longer than a reference one
	float leftMaxDropOut = 0.7;			/// The minimum ratio of height to consider an allele that is shorter than a reference one
		
	int motiveLength = marker.motiveLength;
	
	for (int i = 0; i < nPeaks; i++) {
		int index = (int)markerPeakIndices[i];
		if(markerPeaks[index].parentPeak >= 0) {
			/// If the peak was considered as a child of another peak, we don't need to examine its neighbors
			continue;
		}
		/// We evaluate neighboring peaks that are at the left. We consider all peaks that are shorter
		characterizeNeighbors(markerPeaks, nPeaks, index, 1.0, motiveLength, true);
		
		/// We evaluate neighboring peaks that are at the right. Note that for peaks arising from stuttering,
		/// we will not consider peaks that are too high as child peaks. Normally, stuttering is weaker on the right
		characterizeNeighbors(markerPeaks, nPeaks, index, rightMaxDropOut, motiveLength, false);
	}
	
	/// an array to store the peaks considered as alleles
	MarkerPeak retainedPeaks[nPeaks];
	MarkerPeak additionalPeaks[nPeaks];
	int nRetained = 1;					/// number of peaks considered as alleles
	int nAdditional = 0;
	int16_t ploidy = marker.ploidy;
	/// We consider the tallest peak as retained
	MarkerPeak lastRetained = markerPeaks[markerPeakIndices[0]];
	retainedPeaks[0] = lastRetained;
		
	for (int i = 1; i < nPeaks; i++) {
		/// We evaluate peaks by decreasing height
		long index = markerPeakIndices[i];
		MarkerPeak peak = markerPeaks[index];
		float ratio = peak.height / lastRetained.height;
		if(peak.parentPeak < 0) {
			/// The peak has no parent (hence it could represent an allele)
			float diffSize = peak.size - lastRetained.size;
			if(annotateSuppPeaks && ((diffSize < 0 && ratio < leftMaxDropOut) || (diffSize > 0 && ratio < rightMaxDropOut && ratio * diffSize < 4))) {
				/// The peak is too short.
				if(ratio > 0.2 || (peak.nChildPeaks >= 1 && ratio > 0.12)) {
					/// We consider it as an additional peak if it is not too short or has several child peaks
					/// This is to avoid considering insignificant peaks
					additionalPeaks[nAdditional++] = peak;
					continue;
				}
			} else if(nRetained < ploidy) {
				/// We retain the peak
				lastRetained = peak;
				retainedPeaks[nRetained++] = peak;
			} else if(annotateSuppPeaks) {
				/// If there are more peaks than possible alleles of the locus, we may consider this peak as additional
				if(ratio > 0.2 || (peak.nChildPeaks > 0 && ratio > 0.12)) {
					additionalPeaks[nAdditional++] = peak;
					continue;
				}
			}
		} else if(annotateSuppPeaks && peak.stutterRatio > 2 && ratio > 0.2) {
			/// For child peaks, we consider additional those that are abnormally high
			additionalPeaks[nAdditional++] = peak;
		}
	}

	free(markerPeakIndices);
	
	NSMutableSet *remainingFragments = self.additionalFragments.mutableCopy;
	
	if(nAdditional > 0) {
		for (int i = 0; i < nAdditional; i++) {
			MarkerPeak peak = additionalPeaks[i];
			Allele *closestFragment;	/// We reuse fragments that are the closest to the peak to avoid unnecessary movements of labels if the genotype is shown.
			int closestDistance = INT_MAX;
			for(Allele *fragment in remainingFragments) {
				int distance = abs(fragment.scan - peak.scan);
				if(distance < closestDistance) {
					closestDistance = distance;
					closestFragment = fragment;
					if(distance == 0) {
						break;
					}
				}
			}
			
			if(!closestFragment) {
				closestFragment = [[Allele alloc] initWithGenotype:self additional:YES];
			} else {
				[remainingFragments removeObject:closestFragment];
			}
			/// Setting the scan also makes the allele compute its size, but since we already know the peak size,
			/// we can make things faster by avoiding using the normal setter.
			[closestFragment managedObjectOriginal_setScan:peak.scan];
			[closestFragment managedObjectOriginal_setSize:peak.size];
			[closestFragment findNameFromBins];
		}
	}
	
	if(remainingFragments.count > 0) {
		/// We remove remaining additional fragments, but we use a non-mutable set because apparently,
		/// deleting  alleles may mutate the set (I had an exception thrown). I don't understand how.
		NSSet *fragmentsToRemove = [NSSet setWithSet:remainingFragments];
		for(Allele *fragmentToRemove in fragmentsToRemove) {
			[fragmentToRemove removeFromGenotypeAndDelete];
		}
	}
	
	/// we now assign alleles
	if(nRetained > 0) {
		for(Allele *allele in self.assignedAlleles) {
			/// By default, the first marker peak will take the allele. If there is more alleles than peaks, this creates homozygotes.
			MarkerPeak *closestPeak = &retainedPeaks[0];
			if(nRetained > 1) {
				int closestDistance = INT_MAX;
				for (int i = 0; i < nRetained; i++) {
					MarkerPeak *peak = &retainedPeaks[i];
					if(peak->height >= 0) {
						/// Peaks that are already assigned to alleles have a negative height (see below).
						int distance = abs(allele.scan - peak->scan);
						if(distance < closestDistance) {
							closestDistance = distance;
							closestPeak = peak;
							if(distance == 0) {
								break;
							}
						}
					}
				}
			}
			closestPeak->height = -1;	/// Tells that the peak has been used (not very elegant, but convenient).
			[allele managedObjectOriginal_setScan:closestPeak->scan];
			[allele managedObjectOriginal_setSize:closestPeak->size];
			[allele findNameFromBins];
		}
	}
}


/// Characterizes the peaks in the vicinity of a reference peak: whether they belong to the same cluster (arising from the same allele).
/// This function modifies the `parent` and `stutterRatio` of a peak, and `nChildPeaks` (of the reference peak)
/// - Parameters:
///   - markerPeaks: The array of peaks to characterize, including the reference peak, sorted by size in base pairs
///   - nPeaks: The number of peaks in the array.
///   - peakIndex: The index of the reference peak in the array = the peak of which the neighbors are characterized.
///   - maxRatio: The maximum ratio in height (child/reference) to consider a peak as a child of the reference peak.
///   - motive: The length of the repeat motive, used to determine if a neighbor results from stuttering (indel of a motive)
///   - decreasing: Whether neighbors of shorter sizes (at the left) should be inspected. If false, neighbors at the right of the reference peak are inspected
void characterizeNeighbors (MarkerPeak *markerPeaks, int nPeaks, int peakIndex, float maxRatio, int motiveLength, bool decreasing) {
	/// This method inspect peaks by increasing distance from the reference one
	MarkerPeak *refPeak = &markerPeaks[peakIndex];
	float refSize = refPeak->size;
	float refHeight = refPeak->height;
	float stutterPeakSize = refSize;	/// The size of the last characterized peak considered to result from stuttering.
										/// Peaks resulting from stuttering are separated from the reference peaks by multiples of `motiveLength` base pairs
	float adenylPeakSize = refSize;		/// The size of the last inspected peak considered to result from adenylation (+ stuttering)
										/// These peaks are separated from the reference peaks by multiples of `motiveLength` base pairs – 1
	
	int16_t stutterPeakHeight = refHeight;	/// The height of the last peak considered to result from stuttering
	int16_t adenylPeakHeight = refHeight;	/// The height of the last peak considered to result from adenylation +  stuttering
	
	/// variables used to manage the fact that peaks can be inspected by increasing or decreasing order.
	int increment = decreasing? -1 : 1;
	int maxInspected = decreasing? peakIndex : nPeaks - peakIndex -1;	/// maximum number of peaks to inspect without going out of bounds
	int inspected = 0;			/// number of peaks currently inspected
	int leftStutterIndex = 0;	/// The number of stutter peaks inspected at the left.
	
	for (int i = peakIndex + increment; inspected < maxInspected; i+= increment) {
		inspected++;
		MarkerPeak *inspectedPeak = &markerPeaks[i];

		float ratio = inspectedPeak->height / refHeight;
		if(ratio > 1) {
			/// If the peak is higher than the reference, we can stop as we are in another peak cluster, associated to a taller peak
			return;
		}
		
		float peakSize = inspectedPeak->size;
		float peakHeight = inspectedPeak->height;
		
		float diffSize = fabs(stutterPeakSize - peakSize);
		if(diffSize > motiveLength + 0.5) {
			/// The peak is outside the cluster of possible child peaks.
			return;
		}

		if(diffSize >= motiveLength - 0.5 && diffSize <= motiveLength + 0.5 && ratio < maxRatio) {
			/// The peak is at the right distance of one considered to result from stuttering (of the reference peak)
			leftStutterIndex += decreasing;
			
			float stutterRatio = peakHeight / stutterPeakHeight;
			/// The stutter ratio helps to determine to which cluster the peak belongs.
			/// If the ratio is high, the peak may belong to another peak cluster (clusters can overlap)
			
			if(refPeak->crossTalk == 0 && leftStutterIndex == 1 && stutterRatio >= 0.7 && peakHeight > 200) {
				/// If the inspected peak is high and is the first stutter at the left, we expect another stutter with a high ratio at the left.
				/// Otherwise the inspected peak should be an allele. We don't check that if the reference peak is saturated (its height is unreliable).
				float nextStutterRatio = 0;
				for (int j = i-1; j >= 0; j--) {
					MarkerPeak *nextStutterPeak = &markerPeaks[j];
					float diffSize = fabs(nextStutterPeak->size - peakSize);
					if(diffSize >= motiveLength - 0.5 && diffSize <= motiveLength + 0.5) {
						nextStutterRatio = nextStutterPeak->height / peakHeight;
						break;
					} else if(diffSize > motiveLength + 0.5) {
						break;
					}
				}
				if(nextStutterRatio < stutterRatio/3) {
					/// The next stutter peak is non-existing or much lower, which suggests that the inspected peak is not a stutter, but an allele.
					return;
				}
			}
			
			if(inspectedPeak->parentPeak >= 0 && inspectedPeak->stutterRatio < stutterRatio) {
				/// If the ratio is higher than that already established, the peak likely belongs to another cluster
				/// We return, as any subsequent peak should belong to that cluster.
				return;
			}
			if((ratio > 0.7 && stutterRatio > 2) || (!decreasing && stutterRatio > 1)) {
				return;
			}
			inspectedPeak->parentPeak = peakIndex;
			inspectedPeak->stutterRatio = stutterRatio;
			stutterPeakSize = peakSize;
			stutterPeakHeight = peakHeight;
			refPeak->nChildPeaks++;
		} else {
			/// Due to adenylation, peaks may be offset by 1bp compared to the series of stutter
			float diffSize2 = fabs(adenylPeakSize - peakSize);
			if(diffSize2 < 1.5 || (diffSize2 >= motiveLength - 0.5 && diffSize2 <= motiveLength + 0.5 && ratio < maxRatio)) {
				/// The first condition should be met for a peak purely deriving from adenylation, which should be 1bp away from the reference peak
				/// In that case, the heigh ratio may still be high (depending on PCR condition, the reference or the neighbor can be adenyled)
				float stutterRatio = peakHeight / adenylPeakHeight;
				if(inspectedPeak->parentPeak >= 0 && inspectedPeak->stutterRatio < stutterRatio) {
					return;
				}
				if((ratio > 0.7 && stutterRatio > 2) || (!decreasing && stutterRatio > 1)) {
					return;
				}
				inspectedPeak->parentPeak = peakIndex;
				inspectedPeak->stutterRatio = stutterRatio;
				adenylPeakSize = peakSize;
				adenylPeakHeight = peakHeight;
				refPeak->nChildPeaks++;
			} else if(peakHeight < stutterPeakHeight && ratio < maxRatio) {
				//decreasing && ratio < 0.5 && refPeak->size - peakSize < motiveLength - 0.5
				/// Sometimes, a short peak does not follow a clear pattern.
				/// It's unclear what causes this, but we don't consider it an allele if it is shorter than the last stutter peak.
					inspectedPeak->parentPeak = peakIndex;
				refPeak->nChildPeaks++;
			}
		}
	}
}

- (void)binAlleles {
	BOOL foundAllele = NO;
	for(Allele *allele in self.alleles) {
		if(!foundAllele && allele.scan > 0) {
			foundAllele = YES;
		}
		[allele findNameFromBins];
	}
	self.status = foundAllele? genotypeStatusAutomatic : genotypeStatusNoPeak;
}

#pragma mark - managing allele properties


-(void)contextDidChange:(NSNotification *)notification {
	NSSet *changedObjects = [notification.userInfo valueForKey:NSUpdatedObjectsKey];
	NSArray *alleles = self.alleles.allObjects;
	for(id object in changedObjects) {
		if(object == self || [alleles indexOfObject:object] != NSNotFound) {
			self.assignedAlleles = nil;
			self.additionalFragments = nil;
			break;
		}
	}
}


- (NSSet *)assignedAlleles {
	if(!_assignedAlleles && self.alleles.count  > 0) {
		_assignedAlleles = [self.alleles filteredSetUsingPredicate:assignedAllelePredicate];
	}
	return _assignedAlleles;
}


- (void)setAssignedAlleles:(NSSet *)assignedAlleles {
	_assignedAlleles = assignedAlleles;
	self.sortedAlleles = nil;
}


- (NSSet *)additionalFragments {
	if(!_additionalFragments && self.alleles.count  > 0) {
		_additionalFragments = [self.alleles filteredSetUsingPredicate:additionalFragmentPredicate];
	}
	return _additionalFragments;
}


- (void)setAdditionalFragments:(NSSet *)additionalFragments {
	_additionalFragments = additionalFragments;
	self.sortedAdditionalFragments = nil;
}


- (NSArray *)sortedAlleles {
	if(!_sortedAlleles) {
		NSArray *assignedAlleles = self.assignedAlleles.allObjects;
		if(assignedAlleles.count < 2) {
			_sortedAlleles = assignedAlleles;
		} else {
			_sortedAlleles = [assignedAlleles sortedArrayUsingComparator:^NSComparisonResult(Allele * obj1, Allele * obj2) {
				if(obj1.size < obj2.size) {
					return NSOrderedAscending;
				}
				return NSOrderedDescending;
			}];
		}
	}
	return _sortedAlleles;
}


- (void)setSortedAlleles:(NSArray<Allele *> *)sortedAlleles {
	_sortedAlleles = sortedAlleles;
	self.allele1 = nil;
	self.allele2 = nil;
}


-(NSArray *)sortedAdditionalFragments {
	if(!_sortedAdditionalFragments) {
		NSArray *additionalFragments = self.additionalFragments.allObjects;
		if(additionalFragments.count < 2) {
			_sortedAdditionalFragments = additionalFragments;
		} else {
			_sortedAdditionalFragments = [additionalFragments sortedArrayUsingComparator:^NSComparisonResult(Allele * obj1, Allele * obj2) {
				if(obj1.size < obj2.size) {
					return NSOrderedAscending;
				}
				return NSOrderedDescending;
			}];
		}
	}
	return _sortedAdditionalFragments;
}


- (void)setSortedAdditionalFragments:(NSArray *)sortedAdditionalFragments {
	_sortedAdditionalFragments = sortedAdditionalFragments;
	self.additionalFragmentString = nil;
}


- (Allele *)allele1 {
	if(!_allele1) {
		_allele1 = self.sortedAlleles.firstObject;
	}
	return _allele1;
}


- (Allele *)allele2 {
	if(!_allele2 && self.sortedAlleles.count == 2) {
		_allele2 = self.sortedAlleles.lastObject;
	}
	return _allele2;
}


- (NSString *)additionalFragmentString {
	if(!_additionalFragmentString) {
		NSArray *names = [self.sortedAdditionalFragments valueForKeyPath:@"@unionOfObjects.sizeAndName"];
		_additionalFragmentString = [names componentsJoinedByString:@" "];
	}
	return _additionalFragmentString;
}


#pragma mark - validation methods

/// the designated initializers should ensure that the relationships are set properly, but we have validations anyway
/// the reported errors are not informative to the user and they wouldn't know of to correct them. They indicate errors in the code.

- (BOOL)validateSample:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	Chromatogram *sample = *value;
	for(Genotype *genotype in sample.genotypes) {
		if(genotype != self && genotype.marker == self.marker) {
			if (error != NULL) {
				NSString *reason = [NSString stringWithFormat:@"The genotype cannot be applied to sample '%@' because it already has a genotype for marker '%@'.", sample.sampleName, self.marker.name];
				*error = [NSError managedObjectValidationErrorWithDescription:reason suggestion:@"" object:self reason:reason];
				
			}
			return NO;
		}
	}
	/// we cannot validate a sample if its panel doesn't include our marker
	if(![sample.panel.markers containsObject:self.marker]) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"The genotype at marker '%@' cannot be applied to sample '%@' because the panel applied to the sample doesn't have this marker.", self.marker.name, sample.sampleName];
			*error = [NSError managedObjectValidationErrorWithDescription:reason suggestion:@"" object:self reason:reason];

		}
		return NO;
	}
	return YES;
}


- (BOOL)validateMarker:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	/// we cannot validate a sample if its panel doesn't include our marker
	Mmarker *marker = *value;
	if(![self.sample.panel.markers containsObject:marker]) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"The genotype of sample '%@' cannot use marker '%@' because it is not part of the sample's panel.", self.sample.sampleName, marker.name];
			*error = [NSError managedObjectValidationErrorWithDescription:reason suggestion:@"" object:self reason:reason];

		}
		return NO;
	}
	return YES;
}


- (BOOL)validateAlleles:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	/// we cannot validate a sample if its panel doesn't include our marker
	NSSet *alleles = *value;
	if([alleles filteredSetUsingPredicate:assignedAllelePredicate].count != self.marker.ploidy) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"The number of alleles of sample '%@' doesn't match the ploidy if marker '%@'.", self.sample.sampleName, self.marker.name];
			*error = [NSError managedObjectValidationErrorWithDescription:reason suggestion:@"" object:self reason:reason];

		}
		return NO;
	}
	
	for (Allele *allele in alleles) {
		if(allele.trace.channel != self.marker.channel) {
			NSLog(@"trace: %d, marker: %d", allele.trace.channel, self.marker.channel);
			if (error != NULL) {
				NSString *reason = [NSString stringWithFormat:@"An allele of a genotype from sample '%@' is associated with a trace that doesn't have the channel of marker '%@'", self.sample.sampleName, self.marker.name];
				*error = [NSError managedObjectValidationErrorWithDescription:reason suggestion:@"" object:self reason:reason];

			}
			return NO;
		}
	}
	return YES;
}

#pragma mark - other setters and getters

-(void)setSample:(Chromatogram * )sample {
	BOOL shouldDelete = self.sample != nil && sample == nil && !self.deleted;		/// a genotype without a sample must be deleted
	[self managedObjectOriginal_setSample:sample];
	if(shouldDelete) {
		[self.managedObjectContext deleteObject:self];
	}
}


-(void)setMarker:(nullable Mmarker * )marker {
	BOOL shouldDelete = self.marker != nil && marker == nil && !self.deleted;		/// a genotype without a marker must be deleted
	[self managedObjectOriginal_setMarker:marker];
	if(shouldDelete) {
		[self.managedObjectContext deleteObject:self];
	}
}


- (void)prepareForDeletion {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - offset management


MarkerOffset MakeMarkerOffset(float intercept, float slope) {
	MarkerOffset offset;
	offset.intercept = intercept;
	offset.slope = slope;
	return offset;
}


const MarkerOffset MarkerOffsetNone = {0.0, 1.0};



- (void)setOffsetData:(nullable NSData *)offsetData {

	[self managedObjectOriginal_setOffsetData:offsetData];
	for (Allele *allele in self.alleles) {
		[allele computeSize];
	}
	if(self.status != genotypeStatusNotCalled) {
		self.status = genotypeStatusSizingChanged;
	}
}


- (MarkerOffset)offset {
	NSData *offsetData = self.offsetData;
	if(offsetData.length == sizeof(MarkerOffset)) {
		const MarkerOffset *offset = offsetData.bytes;
		return *offset;
	}
	return MarkerOffsetNone;
}


- (BaseRange)range {
	float start = self.marker.start;
	float end = self.marker.end;
	if(self.offsetData) {
		MarkerOffset offset = self.offset;
		start = start * offset.slope + offset.intercept;
		end = end * offset.slope + offset.intercept;
	}
	return MakeBaseRange(start, end - start);
}


- (float)offsetIntercept {
	MarkerOffset offset = self.offset;
	return -offset.intercept / offset.slope;
}


- (float)offsetSlope {
	return self.offset.slope;
}


+ (NSSet<NSString *> *)keyPathsForValuesAffectingOffsetString {
	return [NSSet setWithObject:@"offsetData"];
}


- (NSString *)offsetString {
	if(self.offsetData) {
		MarkerOffset offset = self.offset;
		float intercept = offset.intercept;
		float slope = offset.slope;
		if(intercept == 0.0 && slope == 1.0) {
			return nil;
		}
		return [NSString stringWithFormat:@"%.1f, %.3f", -intercept/slope, 1/slope];
	}
	return nil;
}

# pragma mark - copying and archiving

+(BOOL)supportsSecureCoding {
	return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder {
	[super encodeWithCoder:coder];
	[coder encodeObject:self.marker forKey:@"marker"];			/// we need to encode this relationship as it is not encoded in the opposite direction (a marker doesn't encode its genotypes)
	[coder encodeObject:self.alleles forKey:@"alleles"];		/// we need to encode alleles for the same reasons (encoded with the trace, but this is not the same relationship)

}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		NSSet *alleles = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Allele.class, nil]  forKey:@"alleles"];
		[self managedObjectOriginal_setAlleles:alleles];
		[self managedObjectOriginal_setMarker:[coder decodeObjectOfClass:Mmarker.class forKey:@"marker"]];
	}
	return self;
}


- (id)copy {
	Genotype *copy = [super copy];
	[copy managedObjectOriginal_setMarker: self.marker];
	return copy;
}



@end
