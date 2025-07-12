//
//  SizeStandard.m
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



#import "SizeStandard.h"
#import "SizeStandardSize.h"
#import "PeakLabel.h"
#import "LadderFragment.h"
#import "FragmentLabel.h"
#import "Chromatogram.h"
#import "Trace.h"
#import "TraceView.h"
@import Accelerate;


@interface SizeStandard (DynamicAccessors)

-(void)managedObjectOriginal_setName:(NSString *)name;

@end

@interface SizeStandard ()

@property (nonatomic, readonly) NSString* tooltip;	/// a string used to bind to a tooltip of an image view (padlock) in the size standard table, telling that the size standard cannot be modified.
													/// this solution is a bit lazy. It would be better to separate the model form the UI

@end

CodingObjectKey SizeStandardNameKey = @"name";

@implementation SizeStandard



@dynamic editable, name, sizes, samples;

#pragma mark - sample sizing

/// A structure that describes a peak in the ladder.
typedef  struct LadderPeak {
	int scan;						/// the scan corresponding to the peak tip
	int width;						/// the width of the peak in scans
	short height;					/// its height in fluorescence level
	int area;						/// the area of the peak = sum of fluorescence levels from first scan to last scan within the peak
	float size;						/// the size in base pairs that is assigned to the peak. Negative is no size is assigned
	float offset;					/// difference between size and the size computed given the scan and sizing properties of the trace
	int crossTalk;					/// see equivalent property in `Peak` struct
	
} LadderPeak;



LadderPeak LadderPeakFromPeak(const Peak *peak, Trace *trace) {
	LadderPeak ladderPeak;
	ladderPeak.scan = peak->startScan + peak->scansToTip;
	ladderPeak.width = peakEndScan(peak) - peak->startScan;
	NSData *fluoData = [trace adjustedDataMaintainingPeakHeights:NO];
	const int16_t *fluo = fluoData.bytes;
	long nScans = fluoData.length/sizeof(int16_t);
	ladderPeak.area = 0;
	int endScan = peakEndScan(peak);
	if(endScan >= nScans) {
		ladderPeak.crossTalk = 0;
		ladderPeak.size = 0;
		ladderPeak.offset = 0;
		return ladderPeak;
	}
	for(int scan = peak->startScan; scan <= endScan; scan++) {
		ladderPeak.area += fluo[scan];
	}
	ladderPeak.height = fluo[ladderPeak.scan];
	ladderPeak.crossTalk = peak->crossTalk;
	ladderPeak.size = -1.0;
	ladderPeak.offset = 0.0;
	return ladderPeak;
}


typedef struct LadderSize {			/// describes a size in a size standard
	float size;						/// in base pairs
	LadderPeak *ladderPeakPTR;		/// pointer to the LadderPeak assigned to this size
	int scan;						/// the scan of the LadderPeak
} LadderSize;


+ (void)sizeSample:(Chromatogram *)sample {
	
	Trace *trace = sample.ladderTrace;
	if(!trace) {
		return;
	}

	SizeStandard *sizeStandard = sample.sizeStandard;
	if(!sizeStandard) {
		return;
	}
	
	/// we retrieve the sizes of fragments in the size standard in ascending order to create an array of LadderSize struct
	NSArray *sortedFragments = [sizeStandard.sizes.allObjects sortedArrayUsingComparator:^NSComparisonResult(SizeStandardSize *size1, SizeStandardSize *size2) {
		if(size1.size < size2.size) {
			return NSOrderedAscending;
		} else {
			return NSOrderedDescending;
		}
	}];
	
	const int sizeCount = (int)sortedFragments.count;
	if(sizeCount < 4){
		/// this should not happen in principle, as we enforce at least 4 sizes per size standard
		/// but if there are fewer, we remove all ladder fragments
		
		trace.fragments = nil;
		/// we still size the sample to get "dummy" sizing parameters, otherwise the sample cannot be displayed
		[sample setLinearCoefsForReadLength:DefaultReadLength];
		return;
	}
	
	LadderSize ladderSizes[sizeCount];									/// we use a variable-length array for this, as nSizes will never be very large
	int i = 0;
	for(SizeStandardSize *fragment in sortedFragments) {
		LadderSize size = {.size = (float)fragment.size, .ladderPeakPTR = NULL, .scan = 0};
		ladderSizes[i++] = size;
	}
	
	NSData *peakData = trace.peaks;
	const int peakCount = (int)peakData.length/sizeof(Peak);  			/// number of peaks in the ladder.
	
	if (peakCount < trace.fragments.count /3 || peakCount < 3) {
		/// if we don't have enough peaks, we don't assign them
		/// we still create ladder fragments, which will have no scan but can still assigned manually on a traceView
		[self setLadderFragmentsForTrace:trace WithSizes:ladderSizes sizeCount:sizeCount];
		[sample setLinearCoefsForReadLength:ladderSizes[sizeCount-1].size + 50.0];
		return;
	}
	
	LadderPeak ladderPeaks[peakCount]; 	/// Array of LadderPeak structs based on the peaks of the trace
	
	/// We try to ignore short peaks that amount to noise, as they can mess with size assignment. For this, we first need to sort peaks by decreasing height (fluo level)
	vDSP_Length indices[peakCount];  /// This requires an array of indices
	float heights[peakCount];
	
	const Peak *peaks = peakData.bytes;
	
	for (vDSP_Length i = 0; i < peakCount; i++) {
		const Peak *peakPTR = &peaks[i];
		LadderPeak newLadderPeak = LadderPeakFromPeak(peakPTR, trace);
		heights[i] = newLadderPeak.height;
		indices[i] = i;
		ladderPeaks[i] = newLadderPeak;
	}
	
	vDSP_vsorti(heights, indices, NULL, peakCount, -1);
	
	/// We compute the peak height below which we will ignore peaks. This involve enumerating peaks by decreasing height.
	/// But we must not stop before we have covered a sufficient scan range
	/// as high artifacts that do not amount to crosstalk sometime  cluster in a narrow range (degraded fragments, camera errors).
	int firstPeakScan = peaks[0].startScan;
	int lastPeakScan = ladderPeaks[peakCount-1].scan;
	int scanDiff = lastPeakScan - firstPeakScan;
	int maxSize = ladderSizes[sizeCount-1].size;
	int minSize = ladderSizes[0].size;
	int leftScan = firstPeakScan + scanDiff * minSize/maxSize; /// We won't stop before finding a peak before this scan
	int rightScan = lastPeakScan - 0.2 * scanDiff; /// and before finding one after that scan
	float minHeight = 0;

	int n = 0, nPeaksInRange = 0;
	for (int i = 0; i < peakCount; i++) {
		vDSP_Length index = indices[i];
		LadderPeak *peakPTR = &ladderPeaks[index];
		if(peakPTR->crossTalk >= 0) {
			int scan = peakPTR->scan;
			if(scan > leftScan && scan < rightScan) {
				nPeaksInRange++;
			}
			if(nPeaksInRange >= sizeCount/2 && n >= sizeCount) {
				/// We stop enumerating when we have enough peaks (which some margin), which cover the scan range
				break;
			}
			minHeight = peakPTR->height;
			n++;
		}
	}
	
	/// We now put pointers to the peak we retain in an array
	LadderPeak *ladderPeakPTRs[peakCount];
	n = 0;
	float sumHeight = 0;
	for (int i = 0; i < peakCount; i++) {
		LadderPeak *ladderPeakPTR = &ladderPeaks[i];
		float height = ladderPeakPTR->height;
		if(height >= minHeight/3 && ladderPeakPTR->crossTalk >= 0) {
			/// We ignore peaks resulting from crosstalk although functions still check for crosstalk for peak selection,
			/// A peak resulting from crosstalk could be valid if a ladder fragment has the same size as a fragment in another channel.
			/// But currently, this peak is ignored. I believe it is safer to let the user assign it manually.
			ladderPeakPTRs[n] = ladderPeakPTR;
			sumHeight++;
			n++;
		}
	}
	
	if (n < 3) {
		[self setLadderFragmentsForTrace:trace WithSizes:ladderSizes sizeCount:sizeCount];
		[sample setLinearCoefsForReadLength:ladderSizes[sizeCount-1].size + 50.0];
		return;
	}
	
	float meanHeight = sumHeight/n;
	
	NSData *bestAssignment = [self assignSizes:ladderSizes toPeaks:ladderPeakPTRs sizeCount:sizeCount peakCount:n meanHeight:meanHeight];
	
	float score = refineAssignments(bestAssignment, ladderSizes, ladderPeaks, peakCount);
	
	if(score < 0) {
		/// currently disabled.
		/// We retry assignments, this time allowing peaks much shorter than average.
		sumHeight = 0;
		int n2 = 0;
		for (int i = 0; i < peakCount; i++) {
			LadderPeak *ladderPeakPTR = &ladderPeaks[i];
			float height = ladderPeakPTR->height;
			if(height*10 >= minHeight && ladderPeakPTR->crossTalk >= 0) {
				ladderPeakPTRs[n2] = ladderPeakPTR;
				sumHeight += height;
				n2++;
			}
			
			if(n2 > n) {
				meanHeight = sumHeight/n2;
				NSData *bestAssignment2 = [self assignSizes:ladderSizes toPeaks:ladderPeakPTRs sizeCount:sizeCount peakCount:n2 meanHeight:meanHeight];
				
				LadderSize ladderSizes2[sizeCount];
				float score2 = refineAssignments(bestAssignment2, ladderSizes2, ladderPeaks, peakCount);
				
				if(score2 > score) {
					[self setLadderFragmentsForTrace:trace WithSizes:ladderSizes2 sizeCount:sizeCount];
					[sample computeFitting];
					return;
				}
			}
		}
	}
	
	[self setLadderFragmentsForTrace:trace WithSizes:ladderSizes sizeCount:sizeCount];
	
	[sample computeFitting];
}


/// Assigns ladder sizes to peaks and returns the assigned sizes.
/// - Parameters:
///   - ladderSizes: Array of `LadderSize` to assign. Sizes will me modified by the method.
///   - ladderPeakPTRs: Array of `LadderPeak` pointers of peaks to assign. These ladder peaks will be modified.
///   - sizeCount: Number of elements in the `ladderSizes` array.
///   - peakCount: Number of elements in the `ladderPeaks` array.
///   - meanHeight: Mean peak height, used for peak assignment. 
+(NSData*) assignSizes:(LadderSize*)ladderSizes toPeaks:(LadderPeak**)ladderPeakPTRs
			 sizeCount:(int)sizeCount peakCount:(int)peakCount meanHeight:(float) meanHeight {
	float bestScore = -1;
	int minSizeCount = 2; 				/// minimum number of assigned sizes to consider the results
	const float goodScore = 0.8; 		/// threshold for good quality score
	NSData *bestAssignment = [NSData dataWithBytes:ladderSizes length:sizeCount*sizeof(ladderSizes)];	

	/// We assign the first peak (in scan number) to the first size, the last peak to the last size.
	/// We will assign other intermediate peaks to intermediate sizes (based on proximity).
	/// We reiterate this by incrementing the first peak and decrementing the last peak, in case they were wrong (very common for first peaks, due to artifact at the start of the trace).
	/// We also decrement the last size to assign, which may be missing (electrophoresis might have stopped too soon and the longer fragments may be missing).

	for (int lastPeakIndex = peakCount-1; lastPeakIndex+1 >= minSizeCount; lastPeakIndex--) {
		/// decrementing last peak index
		for (int lastSizeIndex = sizeCount-1; lastSizeIndex+1 >= minSizeCount; lastSizeIndex--) {
			/// decrementing last size index
			ladderPeakPTRs[lastPeakIndex]->size = ladderSizes[lastSizeIndex].size;
			for (int firstPeakIndex = 0;  firstPeakIndex <= lastPeakIndex - minSizeCount + 1; firstPeakIndex++) {
				/// incrementing first peak index
				assignPeaksToSizes(ladderPeakPTRs, ladderSizes, firstPeakIndex, lastPeakIndex, lastSizeIndex, sizeCount, meanHeight);
				
				int nAssigned = 0;
				float a,b;
				float currentScore = sizingScoreForSizes(ladderSizes, sizeCount, &nAssigned, &a, &b, false);
				
				if(nAssigned >= minSizeCount) {
					if(currentScore > bestScore) {
						bestScore = currentScore;
						bestAssignment = [NSData dataWithBytes:ladderSizes length:sizeCount*sizeof(LadderSize)];
					}
					
					if(currentScore >= goodScore) {
						/// if we consider that the assignment is good enough, we won't look for iterations involving a lower number of sizes
						minSizeCount = nAssigned;
					}
				}
			}
		}
	}
	return bestAssignment;
}


/// Assigns ladder peaks to sizes of a size standard.
/// - Parameters:
///   - ladderPeakPTRs: Array of `LadderPeak` pointers.
///   - ladderSizes: Array of `LadderSize`, to which peaks will be assigned.  On output, their `scan` and `ladderPeakPTR` members will correspond to assigned peaks.
///   - firstPeakIndex: Index before which peaks of`ladderPeakPTRs` are ignored.
///   - lastPeakIndex: Index after which peaks of `ladderPeakPTRs` are ignored.
///   - lastSizeIndex: Index after which sizes of `ladderSizes` will not be assigned. Must not exceed `sizeCount`.
///   - sizeCount: Number of sizes in the `ladderSize` array.
///   - meanHeight: The mean height of ladder peaks, used to choose between competing peaks for a size.
void assignPeaksToSizes(LadderPeak **ladderPeakPTRs, LadderSize *ladderSizes, int firstPeakIndex, int lastPeakIndex, int lastSizeIndex, int sizeCount, float meanHeight) {
	LadderPeak *lastPeakPTR = ladderPeakPTRs[lastPeakIndex];
	
	LadderPeak *firstPeakPTR = ladderPeakPTRs[firstPeakIndex];
	/// we compute the slope and intercept of the line passing through the first and last peak (x = scan number, y = size)
	float slope = (lastPeakPTR->size - firstPeakPTR->size) / (lastPeakPTR->scan - firstPeakPTR->scan);
	float intercept = (lastPeakPTR->size + firstPeakPTR->size)/2 - slope * (lastPeakPTR->scan + firstPeakPTR->scan)/2;
	
	/// we define a local slope and intercept, which we will use to predict the location of a ladder fragment
	/// (the relationship with size and scan may not be linear)
	/// we initialize them with the parameters based on the first and last peaks
	float localSlope = slope;
	float localIntercept = intercept;
	/// these parameters will then be based on two adjacent ladder fragments assigned to two sizes
	int leftAssignedSize = lastSizeIndex;
	
	/// We deassign all sizes.
	for (int i = 0; i < sizeCount; i++) {
		ladderSizes[i].ladderPeakPTR = NULL;
		ladderSizes[i].scan = 0;
	}
	ladderSizes[lastSizeIndex].ladderPeakPTR = lastPeakPTR;
	ladderSizes[lastSizeIndex].scan = lastPeakPTR->scan;
	
	int sizeIndex = lastSizeIndex-1;		/// the index of the size the peak will be assigned to
	
	/// we assign peaks to sizes from right to left. This is because the left part of the trace often contains noise
	for(int i = lastPeakIndex-1; i >= 0; i--) {
		LadderPeak *ladderPeakPTR = ladderPeakPTRs[i];
		ladderPeakPTR->offset = INFINITY;
		for(int j = sizeIndex; j >= 0; j--) {
			/// we inspect sizes from right to left to see which is the most suitable for the peak
			/// to predict the location of the peak to a lower size than the last assigned one, we use the  slope and intercept
			float predictedSize = (j < leftAssignedSize)? localSlope*ladderPeakPTR->scan + localIntercept : slope*ladderPeakPTR->scan + intercept;
			float offset = ladderSizes[j].size - predictedSize;
			float offsetRatio = offset / ladderPeakPTR->offset ;
			if(fabs(offsetRatio) < 1) {
				/// if the peak is closer to the current size than the previous size
				if(offsetRatio <= -0.3 && ladderPeakPTR->offset > -10) {
					/// we do further inspection if the current size isn't much closer (not more than 3x closer) and if the previous offset is not too large.
					/// The negative ratio means that the peak is between both sizes (previous offset is negative, current is positive)
					/// We do these checks to make sure the previous size isn't skipped with no peak assigned
					LadderSize previousSize = ladderSizes[j+1];
					/// if the previous size has no peak or has a peak of poor quality peak (crosstalk, etc.), we don't take the current size and keep the previous
					if (previousSize.ladderPeakPTR == NULL) {
						break;
					}
					LadderPeak previous = *previousSize.ladderPeakPTR;
					if(previous.crossTalk < 0 || previous.height < meanHeight / 3 || (previous.area/previous.height) > (ladderPeakPTR->area/ladderPeakPTR->height)*2) {
						break;
					}
				}
				if(j == leftAssignedSize -1 && leftAssignedSize != lastSizeIndex) {
					/// if the peak appears to correspond to a size that is lower than the last assigned,
					/// we replace the current slope with the local slope (same for intercept)
					slope = localSlope;
					intercept = localIntercept;
				}
				ladderPeakPTR->offset = offset;
				sizeIndex = j;
			} else {
				break;  /// when the offset starts to get higher than the previous one, we can exit (since sizes are decreasing)
			}
		}
		/// based on the offset, we assign the peak to the size (assignment is not guaranteed because some other peaks may be better)
		BOOL assigned = assignPeakToSize(ladderPeakPTR, &ladderSizes[sizeIndex], meanHeight);

		/// if the peak is assigned, we compute the local slope and intercept based on the peaks assigned to this size and to the previous size
		if(assigned && fabsf(ladderPeakPTR->offset) < 30)  {
			if(sizeIndex < leftAssignedSize) {
				leftAssignedSize = sizeIndex;
			}
			LadderPeak *leftPeak = ladderPeakPTR;
			LadderPeak *rightPeak = lastPeakPTR;
			
			localSlope = (rightPeak->size - leftPeak->size) / (rightPeak->scan - leftPeak->scan);
			localIntercept = (rightPeak->size + leftPeak->size)/2 - localSlope * (rightPeak->scan + leftPeak->scan)/2;
		}
	}
}


/// Tries to assign a ladder peak to a size and returns whether the assignment was made.
///
/// Depending on the `ladderPeakPTR` member of `ladderSizePTR`,
/// the method may not replace it by `candidatePeakPTR` (if this peak appear less suited) and may return `NO`.
/// - Parameters:
///   - candidatePeakPTR: Pointer to the peak to assign to the size.
///   - ladderSizePTR: Pointer to the size that may be assigned to the peak pointed by `candidatePeakPTR`.
///   - meanHeight: A mean value of peak height that is used to asses peak quality.
BOOL assignPeakToSize(LadderPeak *candidate, LadderSize *ladderSizePTR, float meanHeight) {
	candidate->size = -1;				/// we deassign the peak
	if(fabs(candidate->offset) > 15) {
		/// if the peak offset is just too large, we cannot assign it
		return NO;
	}
	/// we check if a previously inspected peak is assigned to this size
	if(ladderSizePTR->ladderPeakPTR != NULL) {
		/// in that case, the candidate may replace the resident for this size
		LadderPeak *resident = ladderSizePTR->ladderPeakPTR;
		/// we use the "shape" of the peaks, which represents their flatness (area/height). A peak that is too flat may represent an artifact.
		float residentShape = (float)resident->area / resident->height;
		float candidateShape = (float)candidate->area / candidate->height;
		bool replace = false ;				/// will be true if the resident peak needs to be replaced by the candidate
		bool closer = fabs(candidate->offset) < fabs(resident->offset);
		bool crossTalk = candidate->crossTalk < 0;
		if(resident->crossTalk < 0) {
			if(!crossTalk || closer) {
				/// this is the case if the resident is crosstalk and the candidate isn't, or is closer
				replace = true;
			}
		} else if(residentShape > candidateShape*3 && resident->height < meanHeight/2) {
			/// if the resident peak isn't crosstalk, but is too flat or too short
			if(!crossTalk && ((candidateShape <= residentShape*3 && candidate->height >= meanHeight/3) || closer)) {
				replace = true;				/// the candidate replaces it doesn't have these defects, or is closer
			}
		} else if(!crossTalk && candidateShape <= residentShape*3 && candidate->height >= meanHeight/3 && closer) {
			replace = true;					/// else the candidate must have no defect, no crosstalk and be closer
		}
		if(replace) {
			/// if the resident is replaced, we de-assign it
			ladderSizePTR->ladderPeakPTR->size = -1;
		} else {
			return NO;
		}
	}
	ladderSizePTR->ladderPeakPTR = candidate;
	ladderSizePTR->scan = candidate->scan;
	candidate->size = ladderSizePTR->size;
	return YES;
}


/// returns slope between scan and size of peaks using ordinary least squares
float regressionForPeaks (const LadderPeak *peaks, int peakCount, int first, float *intercept) {
	float sumXX=0, sumXY=0, sumX=0, sumY=0, slope;
	for (int i = first; i < peakCount+first; i++) {
		sumXX += peaks[i].scan * peaks[i].scan;
		sumX += peaks[i].scan;
		sumY += peaks[i].size;
		sumXY += peaks[i].scan * peaks[i].size;
	}
	slope= (peakCount*sumXY - sumX*sumY)/(peakCount*sumXX - pow(sumX, 2));
	*intercept = (sumY - slope*sumX)/peakCount;
	return slope;
}


/// Computes a score of sizing quality from 0 to 1, based on assignment of sizes (in base pairs), to scans.
///
/// The score is based on linear regression where
/// the predictor is the `scan` of each `LadderSize` element and the response variable  its `size`.
/// - Parameters:
///   - sizes: Array of `LadderSize` objects.
///   - sizeCount: Number of elements the `sizes` array.
///   - usedCount: On output, the number of assigned ladder sizes, i.e., whose `scan` is greater than 0.
///   - emphasizeOnOffset: If `true` the score puts more emphasis on the offset between the predicted
///   size and the observed size. Otherwise, more emphasis is put on the proportion of sizes that are unassigned (`sizeCount` – `usedCount`).
float sizingScoreForSizes(LadderSize *sizes, int sizeCount, int *usedCount, float *slope, float*intercept, bool emphasizeOnOffset) {
	float sumXX=0, sumXY=0, sumX=0, sumY=0;
	int used = 0;
	LadderSize *usedSizePTRs[sizeCount];
	for (int i = 0; i < sizeCount; i++) {
		LadderSize *sizePTR = &sizes[i];
		int scan = sizePTR->scan;
		if(scan > 0) {
			sumXX += scan * scan;
			sumX += scan;
			sumY += sizePTR->size;
			sumXY += scan * sizePTR->size;
			usedSizePTRs[used] = sizePTR;
			used++;
		}
	}
		
	*usedCount = used;
	*slope= (used*sumXY - sumX*sumY)/(used*sumXX - sumX*sumX);
	*intercept = (sumY - *slope*sumX)/used;
	
	float maxDiffOffset = 0.0;
	float previousOffset = 0.0;
	for (int i = 0; i < used; i++) {
		LadderSize *sizePTR = usedSizePTRs[i];
		float offset = sizePTR->size -  (*slope*sizePTR->scan + *intercept);
		if(i > 0) {
			float diffOffset = previousOffset-offset;
			if(emphasizeOnOffset) {
				diffOffset *= diffOffset;
			}
			diffOffset = fabs(diffOffset) / abs(usedSizePTRs[i-1]->scan - sizePTR->scan);
			if(diffOffset > maxDiffOffset) {
				maxDiffOffset = diffOffset;
			}
		}
		previousOffset = offset;
	}
	float diffSizeCount = sizeCount - used;
	float score = emphasizeOnOffset?  (1 - maxDiffOffset/0.3 - 0.1*diffSizeCount) : (1 - maxDiffOffset*3 - sqrt(diffSizeCount/sizeCount));
	
	return MAX(0, score);
}


float refineAssignments(NSData *sizeData, LadderSize *sizes, LadderPeak *ladderPeaks, int peakCount) {
	int sizeCount = (int)(sizeData.length/sizeof(LadderSize));
	const LadderSize *dataSize = sizeData.bytes;
	for (int i = 0; i < sizeCount; i++) {
		sizes[i] = dataSize[i];
	}

	float slope = 0, intercept = 0, a = 0, b = 0;
	int used = 0;
	float refScore = sizingScoreForSizes(sizes, sizeCount, &used, &slope, &intercept, true);
	int currentPeakIndex = 0;
	
	for (int i = 0; i < sizeCount; i++) {
		float maxOffset = 5;
		LadderSize *sizePTR = &sizes[i];
		sizePTR->ladderPeakPTR = NULL;
		int scan = sizePTR->scan;
		if(scan > 0) {
			/// We measure the score as if the size was not assigned.
			sizePTR->scan = 0;
			float scoreWithoutSize = sizingScoreForSizes(sizes, sizeCount, &used, &a, &b, true);
			if((scoreWithoutSize - refScore) < 0.3) {
				/// If the difference is score is not too big, we consider the assignment good enough and we restore the scan
				sizePTR->scan = scan;
			} else {
				refScore = scoreWithoutSize;
				slope = a; intercept = b;
				maxOffset = (scan * slope + intercept) - sizePTR->size;
			}
		}
		if(sizePTR->scan <= 0) {
			for (int peakIndex = currentPeakIndex; peakIndex < peakCount; peakIndex++) {
				LadderPeak *peakPTR = &ladderPeaks[peakIndex];
				int peakScan = peakPTR->scan;
				float sizeOffset = (peakScan * slope + intercept) - sizePTR->size;
				if(fabsf(sizeOffset) >= maxOffset) {
					if(sizeOffset < 0) {
						continue;
					} else {
						currentPeakIndex = peakIndex;
						break;
					}
				}
				assignPeakToSize(peakPTR, sizePTR, 0);
				float newScore = sizingScoreForSizes(sizes, sizeCount, &used, &a, &b, true);
				if(newScore > refScore) {
					refScore = newScore;
					slope = a; intercept = b;
					currentPeakIndex = peakIndex+1;
				} else {
					sizePTR->scan = 0;
					sizePTR->ladderPeakPTR = NULL;
					if(sizeOffset > 0) {
						currentPeakIndex = peakIndex;
						break;
					}
				}
			}
		}
	}
	return refScore;
}


/// Sets the `fragments` relationship of the receiver given the LadderSizes provided in an array.
///
/// This method assumes that the receiver is a ladder. If creates `LadderFragments` objects if required.
/// - Parameters:
///   - sizes: An array of sizes to be represented by ladder fragments.
///   - nSizes: The number of elements in the `sizes` array.
+ (void)setLadderFragmentsForTrace:(Trace *) trace WithSizes:(LadderSize *)sizes sizeCount:(int)sizeCount {
	NSSet *ladderFragments = trace.fragments;
	bool *alreadyAssigned = calloc(sizeCount, sizeof(bool));
	NSMutableSet *reusedFragments = NSMutableSet.new;
	NSMutableArray *remainingFragments = [NSMutableArray arrayWithArray:ladderFragments.allObjects];
	
	/// We try to assign a size to a ladder fragment that already has this size (if any).
	for(LadderFragment *fragment in ladderFragments) {
		for (NSInteger i = 0; i < sizeCount; i++) {
			if(!alreadyAssigned[i]) {
				const LadderSize *ladderSize = &sizes[i];
				float size = ladderSize->size;
				if(size == fragment.size) {
					alreadyAssigned[i] = true;
					int scan = ladderSize->scan;
					if(scan != fragment.scan) {
						fragment.scan = scan;
					}
					[reusedFragments addObject:fragment];
					[remainingFragments removeObject:fragment];
					break;
				}
			}
		}
	}
	
	NSInteger nRemainingFragments = remainingFragments.count;
	if(reusedFragments.count < sizeCount) {
		for (int i = 0; i < sizeCount; i++) {
			if(!alreadyAssigned[i]) {
				const LadderSize *ladderSize = &sizes[i];
				LadderFragment *fragment;
				if(nRemainingFragments > 0) {
					fragment = remainingFragments[nRemainingFragments-1];
					nRemainingFragments--;
				} else {
					fragment = [[LadderFragment alloc] initWithEntity:LadderFragment.entity insertIntoManagedObjectContext:trace.managedObjectContext];
				}
				int scan = ladderSize->scan;
				if(scan != fragment.scan) {
					fragment.scan = scan;
				}
				fragment.size = ladderSize->size;
				[reusedFragments addObject:fragment];
			}
		}
	}
	
	free(alreadyAssigned);
	alreadyAssigned = NULL;
	trace.fragments = reusedFragments;
	
}


#pragma mark - general management and validation methods

- (void)autoName {
	NSArray<NSString *> *existingNames = [self.siblings valueForKeyPath:@"@unionOfObjects.name"];
	NSString *prefix = self.managedObjectContext.concurrencyType == NSMainQueueConcurrencyType? @"-copy" : @"-imported";
	
	if (existingNames.count > 0) {
		NSString *candidateName;
		int i = 1;
		while(true) {
			NSString *suffix = i == 1? @"" : [NSString stringWithFormat:@" %d",i];
			candidateName =[NSString stringWithFormat:@"%@ %@%@", self.name, prefix, suffix];
			if(![existingNames containsObject:candidateName]) {
				break;
			}
			i++;
		}
		self.name = candidateName;
	}
}


- (NSArray *)siblings {
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:self.entity.name];
	NSArray *siblings = [self.managedObjectContext executeFetchRequest:request error:nil];
	return [siblings arrayByRemovingObject:self];
}

- (NSString *)tooltip {
	return self.editable? @"": @"This size standard cannot be modified";
}



- (BOOL)validateName:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	NSString *name = *value;
	if(name.length == 0) {
		NSString *previousName = self.name;
		if(previousName.length > 0) {
			if([self validateName:&previousName error:nil]) {
				*value = previousName;
				return YES;
			}
		}
	}
	/// we verify is the name is not already used by another size standard.
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:SizeStandard.entity.name];
    NSArray *standards = [self.managedObjectContext executeFetchRequest:request error:nil];
    if(standards) {
        for (SizeStandard *standard in standards) {
            if(standard != self && [name isEqualToString:standard.name]) {
				if (error != NULL) {
					NSString *reason = [NSString stringWithFormat:@"Duplicate size standard name ('%@')", name];
					*error = [NSError managedObjectValidationErrorWithDescription:[NSString stringWithFormat:@"A size standard named '%@' already exists", name]
																	   suggestion:@"Please, use another name."
																		   object:self reason:reason];
				}
                return NO;
            }
        }
    }
   
    return YES;
}


- (BOOL)validateFragments:(id _Nullable __autoreleasing *)valueRef error:(NSError * _Nullable __autoreleasing *)error {
	NSSet *fragments = *valueRef;
	if(fragments.count < 4) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"Size standard '%@' has less than 4 sizes.", self.name];
			*error = [NSError managedObjectValidationErrorWithDescription:reason
															   suggestion:@"Add sizes to this size standard."
																   object:self
																   reason:reason];
		}
		return NO;
	}
	return YES;
}



#pragma mark - archiving/unarchiving

+(BOOL)supportsSecureCoding {
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[super encodeWithCoder:coder];
	[coder encodeObject:self.sizes forKey:@"sizes"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		self.sizes = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, SizeStandardSize.class, nil]  forKey:@"sizes"];
		self.editable = YES;				/// standards imported from folder archives are always editable. Non-editable standards should not be imported anyway (see below), since they are already in the database
	}
	return self;
}


- (BOOL)isEquivalentTo:(__kindof NSManagedObject *)obj {
	if(obj.class != self.class) {
		return NO;
	}
	SizeStandard *standard = obj;
	if(standard.sizes.count != self.sizes.count) {
		return NO;
	}
	NSSet *sizes = [self.sizes valueForKeyPath:@"@distinctUnionOfObjects.size"];		/// equivalence in only based on the sizes of the fragments. We don't check for names.
	NSSet *objSizes = [standard.sizes valueForKeyPath:@"@distinctUnionOfObjects.size"];
	
	if([sizes isEqualToSet: objSizes]) {
		return YES;
	}
	return NO;
}


@end
