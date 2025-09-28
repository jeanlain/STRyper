//
//  Trace.m
//  STRyper
//
//  Created by Jean Peccoud on 18/08/2014.
//  Copyright (c) 2014 Jean Peccoud. All rights reserved.
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



#import "Trace.h"
#import "Chromatogram.h"
#import "TraceView.h"
#import "Mmarker.h"
#import "SizeStandard.h"
#import "SizeStandardSize.h"
#import "LadderFragment.h"
#include <sys/sysctl.h>

@import Accelerate;

CodingObjectKey TraceIsLadderKey = @"isLadder",
TracePeaksKey = @"peaks",
TraceFragmentsKey = @"fragments";

NSString * _Nonnull const previousTraceClassName = @"Trace";

const BaseRange ZeroBaseRange = {.start = 0, .len = 0};

@interface Trace () {
	CGMutablePathRef  path;          /// C array of CGPathRef
	CGPoint *pointsForPath;
	NSUInteger pointCount;
}

/// Fluorescence data (array of 16-bit integers) with baseline "noise" removed.
/// This attribute can be used to draw fluorescence curves in which peaks stand out more.
/// This is not a core data attribute.
@property (nonatomic, readonly, nullable) NSData *adjustedData;

@property (nonatomic, readonly, nullable) NSData *adjustedDataMaintainingPeakHeights;

@end

@interface Trace (DynamicAccessors)
/// to set attributes and relationships that are readonly in the interface file

-(void)managedObjectOriginal_setRawData:(NSData *)rawData;
-(void)managedObjectOriginal_setChannel:(ChannelNumber)channel;
-(void)managedObjectOriginal_setChromatogram:(Chromatogram *)sample;
-(void)managedObjectOriginal_setPeaks:(NSData *)peaks;
-(void)managedObjectOriginal_setPeakThreshold:(int16_t)peakThreshold;

@end


@interface Trace (CoreDataGeneratedAccessors)
/// to set attributes and relationships that are readonly in the interface file

-(void)addFragments:(NSSet *)fragments;
-(void)removeFragments:(NSSet *)fragments;

@end



@implementation Trace {
	__weak NSData *previousPeaks; /// Used to determined if peaks have changed, to update the ``adjustedData`` attribute in this case..
	__weak NSData *previousPeaksM; /// Used to determined if peaks have changed, to update the ``adjustedDataMaintainingPeakHeights`` attribute in this case..

}

@dynamic dyeName, channel, isLadder, maxFluo, peaks, peakThreshold, rawData, fragments, chromatogram;

@synthesize  adjustedData = _adjustedData,
adjustedDataMaintainingPeakHeights = _adjustedDataMaintainingPeakHeights,
visibleRange = _visibleRange, topFluoLevel = _topFluoLevel;


BaseRange MakeBaseRange(float start, float len) {
	BaseRange range;
	range.start = start;
	range.len = len;
	return range;
}



static BOOL appleSilicon;			/// whether the Mac running the application has an Apple SoC.
									/// We use it for drawing optimisations.

+ (void)initialize {
	if (self == [FluoTrace class]) {
		/// We determine if the SoC is from Apple by reading the CPU brand.
		/// There may be a better way by reading the architecture.
		char string[100];
		size_t size2 = 100;
		sysctlbyname("machdep.cpu.brand_string", &string, &size2, nil, 0);
		appleSilicon = strncmp(string, "Apple", 5) == 0;

	}
}


- (instancetype)initWithRawData:(NSData *)rawData addToChromatogram:(Chromatogram *)sample channel:(ChannelNumber)channel {
	if(!sample.managedObjectContext) {
		NSLog(@"the provided sample ('%@') has no managed object context!", sample.sampleName);
		return nil;
	}
	self = [super initWithContext:sample.managedObjectContext];
	if(self) {
		[self managedObjectOriginal_setChromatogram:sample];
		[self managedObjectOriginal_setChannel:channel];
		[self managedObjectOriginal_setRawData:rawData];
	}
	return self;
}


#pragma mark - methods and function related to fluorescence analysis


Peak MakePeak(int32_t startScan, int32_t scansToTip, int32_t scansFromTip, int32_t crossTalk) {
	Peak peak;
	peak.startScan = startScan;
	peak.scansToTip = scansToTip;
	peak.scansFromTip = scansFromTip;
	peak.crossTalk = crossTalk;
	return peak;
}


int32_t peakEndScan(const Peak *peakPTR) {
	return peakPTR->startScan + peakPTR->scansToTip + peakPTR->scansFromTip;
}


- (void)setPeakThreshold:(int16_t)peakThreshold {
	if(peakThreshold < 10) {
		peakThreshold = 10;
	}
	[self managedObjectOriginal_setPeakThreshold:peakThreshold];
	[self findPeaks];
	[self findCrossTalk];
	/// as we may have found new peaks, we look for new ladder fragments
	[SizeStandard sizeSample:self.chromatogram];
}


- (void)findPeaks {
	NSData *rawData = self.rawData;
	int nScans = (int)rawData.length / sizeof(int16_t);
	int16_t peakThreshold = self.peakThreshold;
	float ratio = 0.7;  							/// ratio of minimum fluo next to peak / peak height.
	int maxFluoLevel = 0;   						/// the max fluo level of a trace
	const int16_t *raw = rawData.bytes;
	
	int16_t *adjusted = calloc(nScans, sizeof(int16_t));	/// this will store the adjusted fluo data, after baseline level removal
	
	Peak *peaks = malloc(nScans*sizeof(*peaks));
	bool *isMin = calloc(nScans, sizeof(bool));		/// Whether a scan represents a local minimum in fuorescence

	int nPeaks = 0;
	/// we have several rounds of peak detection and baseline fluo removal.
	/// This is because we outline peaks on adjusted data (with baseline level subtracted) and because the subtraction is better after more than 1 round
	for(int round = 1; round <= 3; round++) {
		if(round == 1)	{
			nPeaks = peakDetect(raw, nScans, peaks, isMin, &maxFluoLevel, peakThreshold, ratio);
			[self setPrimitiveValue:@(maxFluoLevel) forKey:@"maxFluo"];
		}
		else {
			ratio = 0.5;
			nPeaks = peakDetect(adjusted, nScans, peaks, isMin, &maxFluoLevel, peakThreshold, ratio);
		}
		if(nPeaks == 0) {
			break;
		}
		if(round < 3) {
			///we subtract baseline and put results in the adjusted array. Some fluo levels may become negative, but the second round will mitigate that.
			subtractBaseline(raw, peaks, nPeaks, nScans, adjusted, false);
		}
	}
	
	free(isMin);
	isMin = NULL;
	
	if(nPeaks == 0) {
		free(peaks); free(adjusted); peaks = NULL; adjusted = NULL;
		return;
	}
	
	/// we set the peaks. The current peak edges are not close enough from the tips, which isn't ideal for user interaction with peaks.
	/// we set the edge as the closest scan to the tip that has fluorescence 0 (in adjusted data)
	/// or as the scan of a local minimum if the fluo starts to increase > 1.5 times the minimum.
	for (int n = 0; n < nPeaks; n++ ) {
		Peak *peakPTR = &peaks[n];
		int32_t startScan = peakPTR->startScan;
		int32_t tipScan = startScan + peakPTR->scansToTip;
		int32_t i = 0, j = 0, localMin = 0;
		int32_t localMinFluo = adjusted[tipScan];
		for (i = tipScan-1; i > startScan; i--) {
			int16_t fluo = adjusted[i];
			if(fluo <= 0) {
				break;
			}
			if(fluo < localMinFluo) {
				localMin = i;
				localMinFluo = fluo;
			} else if(fluo > localMinFluo*1.5) {
				i = localMin;
				break;
			}
		}
		
		localMinFluo = adjusted[tipScan];
		int32_t endScan = tipScan + peakPTR->scansFromTip;
		for (j  = tipScan+1; j < endScan; j++) {
			int16_t fluo = adjusted[j];
			if(fluo <= 0) {
				break;
			}
			if(fluo < localMinFluo) {
				localMin = j;
				localMinFluo = fluo;
			} else if(fluo > localMinFluo*1.5) {
				j = localMin;
				break;
			}
		}
		
		peakPTR->startScan = i;
		peakPTR->scansToTip = tipScan - i;
		peakPTR->scansFromTip = j - tipScan;
	}
	
	[self managedObjectOriginal_setPeaks:[NSData dataWithBytes:peaks length:nPeaks*sizeof(Peak)]];
	free(peaks);
	free(adjusted);
	peaks = NULL;
	adjusted = NULL;
}



- (NSData*)adjustedData {
	if(!_adjustedData || previousPeaks != self.primitivePeaks) {
		_adjustedData = [self fluoDataWithSubtractedBaselineMaintainingPeakHeight:NO];
	}
	return _adjustedData;
}


- (NSData *)adjustedDataMaintainingPeakHeights {
	if(!_adjustedDataMaintainingPeakHeights || previousPeaksM != self.primitivePeaks) {
		_adjustedDataMaintainingPeakHeights = [self fluoDataWithSubtractedBaselineMaintainingPeakHeight:YES];
	}
	return _adjustedDataMaintainingPeakHeights;
}


- (NSData *)fluoDataWithSubtractedBaselineMaintainingPeakHeight:(BOOL)maintainPeakHeights {
	NSData *peakData = self.peaks;
	if(maintainPeakHeights) {
		previousPeaksM = peakData;
	} else {
		previousPeaks = peakData;
	}
	NSData *fluoData =  self.primitiveRawData;
	if(!fluoData) {
		return nil;
	}
	if(peakData) {
		int nScans = (int)fluoData.length / sizeof(int16_t);
		const int16_t *raw = fluoData.bytes;
		int nPeaks = (int)peakData.length / sizeof(Peak);
		if(nPeaks == 0) {
			return fluoData;
		}
		int16_t *adjusted = malloc(nScans * sizeof(int16_t));
		const Peak *peaks = peakData.bytes;
		
		subtractBaseline(raw, peaks, nPeaks, nScans, adjusted, maintainPeakHeights);
		fluoData = [NSData dataWithBytes:adjusted length:nScans*sizeof(int16_t)];
		free(adjusted);
	}
	return fluoData;
}


- (NSData *)adjustedDataMaintainingPeakHeights:(BOOL)maintainPeakHeights {
	return maintainPeakHeights? self.adjustedDataMaintainingPeakHeights : self.adjustedData;
}


- (int16_t)fluoForScan:(int)scan useRawData:(BOOL)useRawData maintainPeakHeights:(BOOL)maintainPeakHeights {
	NSData *fluoData = useRawData? self.primitiveRawData : [self adjustedDataMaintainingPeakHeights: maintainPeakHeights];
	if(scan < 0 || scan >= fluoData.length/sizeof(int16_t)) {
		return 0;
	}
	const int16_t *fluo = fluoData.bytes;
	return fluo[scan];
}


/// Detects the peak in the fluorescence data and returns the number of peaks detected.
/// - Parameters:
///   - fluo: The fluorescence data in which to find peaks.
///   - nScans: Numbers of data point in the fluorescence data.
///   - peaks: On output, the array of peaks found, in ascending scan order. The provided array must be long enough.
///   - isMin: Wether a scan represents a local minimum.
///   - maxFluo: On output, the maximum value of `fluo`.
///   - fluoThreshold: The minimum fluorescence value to consider a peak = the peak minimum height.
///   - minRatio: The minimum ratio of fluo level  (background / peak tip), to consider a peak
int peakDetect (const int16_t *fluo, int nScans, Peak *peaks, bool *isMin, int *maxFluo, int16_t fluoThreshold, float minRatio) {
	/// A scan is considered a peak tip if its fluo is higher than the threshold and its elevation is at least 1/minRatio higher than both local minima around it
	/// for each peak, we have two minima (both sides), but a minimum is shared between adjacent peaks
	int16_t minLocalFluo = SHRT_MAX, maxLocalFluo = 0;
	int32_t currentMinScan = 0, currentMaxScan = 0, previousMinScan = 0;
	int nPeaks = 0;
	for (int32_t scan = 0; scan < nScans; scan++) {
		int16_t f = fluo[scan];
		if(isMin[scan]) {
			previousMinScan = scan;
			if(nPeaks > 0) {
				Peak *peakPTR = &peaks[nPeaks-1];
				if(peakPTR->scansFromTip < 0) {
					peakPTR->scansFromTip = scan - peakPTR->startScan - peakPTR->scansToTip;
				}
			}
		}
		
		/// We assume we have passed a peak if the current min fluo level is sufficiently less than the current max,
		/// and same for the current fluo (which may not be a local minimum).
		/// This condition is met in the "descending" slope of the peak (at its right)
		if ((maxLocalFluo >= fluoThreshold) && (f < maxLocalFluo * minRatio) && (minLocalFluo < maxLocalFluo * minRatio) && (currentMinScan < currentMaxScan)) {
			Peak *peakPTR = &peaks[nPeaks];
			peakPTR->crossTalk = 0;
			int32_t startScan = previousMinScan > currentMinScan && previousMinScan < currentMaxScan? previousMinScan : currentMinScan;
			peakPTR->startScan =  startScan;
			peakPTR->scansToTip = currentMaxScan - startScan;
			peakPTR->scansFromTip = -1;
			isMin[currentMinScan] = true;
			
			/// we "close" the previous peak.
			if(nPeaks > 0) {
				peakPTR = &peaks[nPeaks-1];
				if(peakPTR->scansFromTip < 0 || peakEndScan(peakPTR) > currentMinScan) {
					peakPTR->scansFromTip = currentMinScan - peakPTR->startScan - peakPTR->scansToTip;
				}
			}
			currentMinScan = scan;					/// in case the current scan just happens to be the minimum between two peaks
			minLocalFluo = f; maxLocalFluo = f;		/// we reset the max and min fluo levels
			nPeaks++;
		}
		
		if (f < minLocalFluo) {
			minLocalFluo = f;
			currentMinScan = scan;
			if(currentMinScan > currentMaxScan) {
				/// as long as we are on the "descending slope" of the peak, we make sure the max local fluo is not taken from this region
				/// (and will be used when the fluo increases again)
				maxLocalFluo = f;
				currentMaxScan = scan;
			}
		} else if (f > maxLocalFluo) {
			maxLocalFluo = f;
			currentMaxScan = scan;
			if(*maxFluo < f) {
				/// we also record the max fluo of the trace, which we will store later
				*maxFluo = f;
			}
		}
	}
	/// We close the last peak
	if(nPeaks > 0) {
		Peak *peakPTR = &peaks[nPeaks-1];
		peakPTR->scansFromTip = currentMinScan - peakPTR->startScan - peakPTR->scansToTip;
	}
	return nPeaks;
}

/// Removes the baseline level in the fluorescence data (read from rawData) given the detected peaks, and place the result in outputData
/// nPeaks in the number of peaks to consider and nScan the number of scans to consider
/// - Parameters:
///   - rawData: The input data.
///   - peaks: The peaks found in the data.
///   - nPeaks: The number of peaks found.
///   - nScans: The number of data points do consider
///   - outputData: The data with baseline fluorescence level subtracted.
///   - maintainPeakHeights: Whether the baseline level subtraction should preserve the height of peaks.
void subtractBaseline (const int16_t *rawData, const Peak *peaks, int nPeaks, int nScans, int16_t *outputData, bool maintainPeakHeights) {
	/// the principle is to draw a straight line between two mins and subtract the height of the line at every scan between these mins (included) from its fluo level.
	/// this height is hereafter called "baseline".
	/// the mins will then have fluo zero.
	/// this can lead to negative fluo for scan that initially have positive fluorescence values.
	
	int previousMin = 0;			/// the scan of the last minimum
	int end = nScans-1;
	for (int i = 0; i < nPeaks; i++) {
		const Peak *peak = &peaks[i];
		int start = peak->startScan;
		end = peakEndScan(peak);
		if(start - previousMin > 0) {
			/// we are between peaks
			subtractBaselineInRange(rawData, outputData, previousMin, start, -1);
		}
		if(end - start > 0) {
			///we are within a peak.
			///If we should not preserve its height, we specify a negative peak height, which is ignored in subtractBaselineInRange().
			int16_t peakHeight = maintainPeakHeights? rawData[start + peak->scansToTip] : -1;
			subtractBaselineInRange(rawData, outputData, start, end, peakHeight);
		}
		previousMin = end;
	}
	if(nScans - end > 0) {
		subtractBaselineInRange(rawData, outputData, end, nScans-1, -1);
	}
}


/// Subtracts the baseline fluorescence level from fluorescence data in a range from start to end, taking into account the max fluo level.
///
/// This allows to maintain the max level (the height of a peak) unchanged.
/// - Parameters:
///   - inputData: The input data.
///   - outputData: The output data with baseline fluo level removed.
///   - start: The start of the range (index in inputData and outputData) in which to remove baseline.
///   - end: The end of the range (index in inputData and outputData) in which to remove baseline.
///   - maxFluo: The maximum fluorescence level within the range.
void subtractBaselineInRange(const int16_t *inputData, int16_t *outputData, int start, int end, int16_t maxFluo) {
	float baseLine = inputData[start];
	
	/// how much the baseline changes between datapoints, which assumes a straight line from the start to the end of the range
	float increment = (inputData[end] - baseLine)/((float)end - start);
	
	for(int i = start; i <= end; i++) {
		int16_t fluo = inputData[i];
		/// the fluo level to subtract is the baseline multiplied by a ratio that is 0 when the fluo correspond to maxFluo and 1 when it is as low as the baseline
		/// but if the maxFluo if ≤ 0, we ignore it and subtract the baseline.
		float ratio = maxFluo > 0? (maxFluo - (float)fluo)/(maxFluo - baseLine) : 1;
		int16_t toSubtract = baseLine * ratio;
		
		if(toSubtract < 0) {
			toSubtract = 0;
		}
		outputData[i] = fluo - toSubtract;
		baseLine += increment;
	}
}



- (void)findCrossTalk {
	Chromatogram *chromatogram = self.chromatogram;
	NSData *peakData = self.peaks;
	NSData *regionData = chromatogram.offscaleRegions;
	long nOffscale = regionData.length/sizeof(OffscaleRegion);
	long nPeaks = peakData.length/sizeof(Peak);
	if(nPeaks == 0) {
		return;
	}
	
	const Peak *peaks = peakData.bytes;
	const OffscaleRegion *regions = regionData.bytes;
	
	NSData *rawData = self.rawData;
	const int16_t *fluo = rawData.bytes;
	long nScans = rawData.length/sizeof(int16_t);
	if(nScans == 0) {
		return;
	}
	Peak *newPeaks = malloc(nPeaks * sizeof(*newPeaks));	/// will contain the peaks with crosstalk information
	NSSet *traces = chromatogram.traces;	/// if we need to check fluorescence data in other traces;
	
	int j = 0;		/// the index of the off-scale region
	for (int i = 0; i < nPeaks; i++) {
		Peak peak = peaks[i];
		peak.crossTalk = 0;
		int scan = peak.startScan + peak.scansToTip;
		int endScan = peakEndScan(&peak);
		int16_t peakTipFluo = fluo[scan];
		
		/// we check if the peak's tip is within an saturated region
		if(peakEndScan(&peak) >= nScans) {
			break;
		}
		
		ChannelNumber offscaleRegionChannel = -1;
		if(nOffscale > 0) {
			while(scan > regions[j].startScan + regions[j].regionWidth && j < nOffscale-1) {
				j++;
			}
			OffscaleRegion region = regions[j];
			int regionStartScan = region.startScan;
			int regionEndScan = regionStartScan + region.regionWidth-1;
			if(scan >= regionStartScan-1 && scan <= regionEndScan+1) {
				/// We allow the region to be just next to the peak, as the peak may be the edge of a "crater" induced by saturation.
				
				offscaleRegionChannel = region.channel;
				/// if it is, we get the saturated channel is the same of the trace
				if(offscaleRegionChannel == self.channel) {
					/// if the peak has saturated the camera, we record the width of the saturated area,
					/// which can be used to determine the size of the peak (as saturation leads to clipping). The larger the area, the bigger the peak.
					peak.crossTalk = region.regionWidth;
				} else {
					/// If the saturated region results from another channel at the peak, we check if the peak results from crosstalk.
					/// To do so, we compare the fluorescence at the peak to the fluo levels at the borders of the saturated region.
					/// If the peak height is more than twice that at both edges, we consider that the peak results from crosstalk
					int16_t leftFluo = 0;
					if(peak.startScan < regionStartScan) {
						leftFluo = regionStartScan > 0? fluo[regionStartScan-1] : fluo[0];
					}
					
					int16_t rightFluo = 0;
					if(endScan > regionEndScan) {
						rightFluo = regionEndScan < nScans-1? fluo[regionEndScan+1] : fluo[nScans-1];
					}
					
					if(leftFluo < peakTipFluo /2 && rightFluo < peakTipFluo / 2) {
						peak.crossTalk = -region.channel - 1;
					} else if(region.regionWidth >= 2 && ((scan <= regionStartScan && peak.scansFromTip <= 2) || (scan >= regionEndScan && peak.scansToTip <= 2))) {
						/// We consider that the peak may be the edge of a crater caused by saturation.
						peak.crossTalk = -region.channel - 1;
					}
					
				}
			}
		}
		
		if (peak.crossTalk == 0 && peakTipFluo < SHRT_MAX * 0.6) {
			/// if the peak has not been considered crosstalk (nor saturated) and is not too high, we check if peaks in other traces may have induced crosstalk.
			/// We first select the trace of highest fluo level at the peak scan (or the one that induced saturation).
			int16_t highestFluo = 0;
			Trace *otherTrace;
			NSData *otherTraceData;
			for(Trace *trace in traces) {
				if(trace != self) {
					if(offscaleRegionChannel >= 0 && trace.channel != offscaleRegionChannel) {
						continue;
					}
					/// We get the max fluo level across other traces
					NSData *traceData = trace.primitiveRawData;
					if(traceData.length/sizeof(int16_t) >= endScan) {
						const int16_t *data = traceData.bytes;
						int16_t rawFluo = data[scan];
						if(rawFluo > highestFluo) {
							highestFluo = rawFluo;
							otherTrace = trace;
							otherTraceData = traceData;
						}
					}
				}
			}
			
			if(!otherTraceData) {
				newPeaks[i] = peak;
				continue;
			}
			
			if(highestFluo > peakTipFluo*1.66 && otherTrace) {
				/// If the fluorescence in another channel is much higher than that of the peak
				/// we find the peak in the other trace that may have induced crosstalk.
				const int16_t* otherTraceFluo = otherTraceData.bytes;
				NSData *otherTracePeakData = otherTrace.peaks;
				const Peak *tracePeaks = otherTracePeakData.bytes;
				NSInteger numPeaks = otherTracePeakData.length / sizeof(Peak);
				
				const Peak *overlappingPeak = NULL;
				for (int i = 0; i < numPeaks; i++) {
					overlappingPeak = &tracePeaks[i];
					if(peakEndScan(overlappingPeak) > scan) {
						break;
					}
				}
				if(overlappingPeak == NULL) {
					newPeaks[i] = peak;
					continue;
				}
				
				int overlappingPeakStart = overlappingPeak->startScan;
				if(overlappingPeakStart >= scan) {
					newPeaks[i] = peak;
					continue;
				}
				/// We then compare the peaks
				int overlappingPeakTip = overlappingPeakStart + overlappingPeak->scansToTip;
				int overlappingPeakEnd = peakEndScan(overlappingPeak);
				float sourcePeakTipFluo = otherTraceFluo[overlappingPeakTip];
				int firstScan = MIN(peak.startScan, overlappingPeakStart);
				int lastScan = MAX(endScan, overlappingPeakEnd);
				
				float ratio = 0, offset = 0, offset2 = 0, combinedAreas = 0, addedAreas = 0; /// Indices that indicate how much peaks are aligned
				
				/// We try to reduce the influence of baseline level by subtracting the height at the first scan fo each peak.
				int16_t startFluo = fluo[peak.startScan];
				int16_t startFluoOvPeak = otherTraceFluo[overlappingPeakStart];
				
				/// To compare peaks, we will reduce the height of the taller peak using this ratio.
				float heightRatio = (peakTipFluo - startFluo) / (sourcePeakTipFluo - startFluoOvPeak);
				if(peak.scansFromTip + peak.scansToTip <= 4 &&  heightRatio < 0.12) {
					/// if the peak is very narrow and much much shorter than the source peak, we will consider it as crosstalk without comparing shapes
					/// because the peak shape is irregular if the peak is very narrow
					ratio = 1;
					combinedAreas = 1;
				} else {
					for (int k = firstScan; k <= lastScan; k++) {
						float currentPeakHeight = MAX(fluo[k] - startFluo, 0);
						float currentOverlappingPeakHeight = MAX((otherTraceFluo[k] - startFluoOvPeak) * heightRatio, 0);
						combinedAreas += MAX(currentPeakHeight, currentOverlappingPeakHeight);
						addedAreas += currentPeakHeight + currentOverlappingPeakHeight;
						
						float diffHeight = currentPeakHeight - currentOverlappingPeakHeight;
						/// If we are past the tip of each peak, we change the sign of the difference in height.
						/// This is quite sensitive to the alignment of both peaks.
						offset += k < scan ? diffHeight : -diffHeight;
						offset2 += k < overlappingPeakTip ? diffHeight : -diffHeight;
					}
					ratio = (addedAreas - combinedAreas) / combinedAreas; /// The percentage of the intersection of peak areas over total area.
				}
				
				if(ratio > 0.3 && fabs(offset)/combinedAreas < 0.3 && fabs(offset2)/combinedAreas < 0.3) {
					peak.crossTalk = -otherTrace.channel -1;
					/// We check if intense peaks in this other channel also induce crosstalk.
					/// If they don't, we conclude that the current peak doesn't results from crosstalk.
					
					int regionIndex = 0;
					for (int i = 0; i < numPeaks; i++) {
						const Peak *tracePeak = &tracePeaks[i];
						int peakScan = tracePeak->startScan + tracePeak->scansToTip;
						
						/// We compute the ratio of heights between the peak and the one that supposedly induced crosstalk.
						float heightRatioAtPeak = otherTraceFluo[peakScan] / sourcePeakTipFluo;
						if(heightRatioAtPeak > 1 && fluo[peakScan] < peakTipFluo * heightRatio/2) {
							/// Another peak at the other channel has not caused a comparable elevation in fluorescence, hence the focus peak may not result from crosstalk.
							/// But we check if the other peak is not in an offscale region, otherwise fluo levels may not be trusted.
							if(nOffscale == 0) {
								peak.crossTalk = 0;
								break;
							}
							
							while(regionIndex < nOffscale-1 && peakScan >= regions[regionIndex].startScan + regions[regionIndex].regionWidth) {
								regionIndex++;
							}
							const OffscaleRegion *region = &regions[regionIndex];
							if(peakScan < region->startScan || peakScan >= region->startScan + region->regionWidth) {
								/// The other peak is not in an offscale region
								peak.crossTalk = 0;
								break;
							}
							
							if(region->channel == otherTrace.channel) {
								/// If the other peak has saturated the camera, we check the scan that is at the left of the saturated region.
								/// Supposedly, its fluorescence is reliable.
								int leftScan = MAX(region->startScan-1, 0);
								if(heightRatioAtPeak >= 1 && fluo[leftScan] < peakTipFluo * heightRatio/2) {
									peak.crossTalk = 0;
									break;
								}
							}
						}
					}
				}
			}
		}
		
		newPeaks[i] = peak;
	}
	
	[self managedObjectOriginal_setPeaks:[NSData dataWithBytes:newPeaks length:nPeaks*sizeof(Peak)]];
	
	free(newPeaks);
	newPeaks = NULL;
}



#pragma mark-
#pragma mark method related to the display of the trace


- (Peak)missingPeakForScan:(int)scan useRawData:(BOOL)useRawData {
	Peak nullPeak = MakePeak(0, 0, 0, 0);
	NSData *fluoData = useRawData? self.primitiveRawData : self.adjustedData;
	const int16_t *fluo = fluoData.bytes;
	long nScans = fluoData.length/sizeof(int16_t);
	if(scan >= nScans) {
		return nullPeak;
	}
	
	/// To look for a peak, we must know where the scan is with respect to other peaks.
	NSData *peakData = self.peaks;
	const Peak* peaks = peakData.bytes;
	long nPeaks = peakData.length/sizeof(Peak);
	
	/// We record the end of the closest peak on the left, and the start of the closest peak on the right
	int leftEnd = 0;
	int rightStart = (int)nScans;
	
	for(int n = 0; n < nPeaks; n++) {
		const Peak *peakPTR = &peaks[n];
		int startScan = peakPTR->startScan;
		int endScan = peakEndScan(peakPTR);
		if(startScan <= scan && endScan >= scan) {
			return nullPeak;		/// If the scan is within an existing peak, we return
		}
		if(scan < startScan) {
			rightStart = startScan;
			break;
		}
		leftEnd = endScan;
	}
	
	/// We scan the fluorescence to find a peak in the area of the scan, avoiding surrounding peaks
	int margin = 15;
	int start = scan - margin;
	
	if(start < leftEnd) {
		start = leftEnd;
	}
	int end = scan + margin;
	if(end > rightStart) {
		end = rightStart;
	}
	
	int16_t max =0;				/// the max fluo found
	int32_t maxScan = start;	/// and the corresponding scan
	for (int i = start; i < end; i++) {
		if(fluo[i] > max) {
			max = fluo[i];
			maxScan = i;
		}
	}
	
	/// We rescan the area around the max scan to find minima and check if this is a true peak (not just a slope)
	start = maxScan - margin;
	if(start < leftEnd) {
		start = leftEnd;
	}
	end = maxScan + margin;
	if(end > rightStart) {
		end = rightStart;
	}
	
	int32_t leftMinScan = start, rightMinScan = end;
	int16_t leftMin = SHRT_MAX, rightMin = SHRT_MAX;
	for (int i = start; i <= end; i++) {
		if((fluo[i] <= leftMin || fluo[i] <= 0) && i < maxScan) {
			leftMin = fluo[i];
			leftMinScan = i;
		}
		if(fluo[i] < rightMin && i > maxScan) {
			rightMin = fluo[i];
			rightMinScan = i;
			if(rightMin <= 0) {
				break;
			}
		}
	}
	
	float ratio = 0.5;		/// the minimum ration min fluo / max fluo
	if(rightMin >= max * ratio || leftMin >= max*ratio) {
		return nullPeak;
	}
	
	/// We also make sure that the left and right minima surround the scan.
	if(scan < leftMinScan || scan > rightMinScan) {
		return nullPeak;
	}
	
	return MakePeak(leftMinScan, maxScan - leftMinScan, rightMinScan - maxScan, 0);
	
}


- (BOOL)insertPeak:(Peak)newPeak {
	
	int32_t tipScan = newPeak.startScan + newPeak.scansToTip;
	NSData *peakData = self.peaks;
	const Peak *peaks = peakData.bytes;
	long nPeaks = peakData.length / sizeof(Peak);
	Peak *newPeaks = malloc((nPeaks+1)*sizeof(*newPeaks));	/// We recreate the peak array with the newPeak inserted
	
	int inserted = 0;
	/// We insert the newPeak at the correct position as the peaks must be sorted by ascending scan number
	for (int i = 0; i <= nPeaks; i++) {
		const Peak *peakI = &peaks[i];
		if(inserted == 0 && (i == nPeaks || peakI->startScan + peakI->scansToTip > tipScan)) {
			/// We insert the peak once we detect the current peak would be at a lower scan or if we have reached the end
			/// We check if there is room for the new peak. It must not overlap surrounding peaks.
			if((i > 0 && peakEndScan(&peaks[i-1]) > newPeak.startScan) || (i < nPeaks && peakI->startScan < peakEndScan(&newPeak)) ) {
				NSLog(@"No room to insert new peak!");
				free(newPeaks);
				newPeaks = NULL;
				return NO;
			}
			
			inserted = 1;
			newPeaks[i] = newPeak;
		}
		if(i < nPeaks) {
			newPeaks[i+inserted] = peaks[i];
		}
	}
	
	[self managedObjectOriginal_setPeaks:[NSData dataWithBytes:newPeaks length:(nPeaks+1)*sizeof(Peak)]];
	
	free(newPeaks);
	newPeaks = NULL;
	return YES;
	
}


- (float)sizeForScan:(int)scan {
	float size = [self.chromatogram sizeForScan:scan];
	if(self.isLadder) {
		return size;
	}
	for(Genotype *genotype in [self.chromatogram genotypesForChannel:self.channel]) {
		Mmarker *marker = genotype.marker;
		if(size >= marker.start && size <= marker.end) {
			MarkerOffset offset = genotype.offset;
			return (size - offset.intercept)/offset.slope;
		}
	}
	return size;
}



#pragma mark - drawing

- (void)prepareDrawPathFromSize:(float)startSize toSize:(float)endSize vScale:(CGFloat)vScale hScale:(CGFloat)hScale leftOffset:(float)leftOffset useRawData:(BOOL)useRawData maintainPeakHeights:(BOOL)maintainPeakHeights minY:(CGFloat)minY {
		
	Chromatogram *sample = self.chromatogram;
	NSData *fluoData = useRawData? self.primitiveRawData : [self adjustedDataMaintainingPeakHeights:maintainPeakHeights];
	const int16_t *fluo = fluoData.bytes;
	long nRecordedScans = fluoData.length/sizeof(int16_t);

	NSData *sizeData = sample.sizes;
	long nScanWithSizes = sizeData.length/sizeof(float);
	if(nScanWithSizes < nRecordedScans) {
		/// this would indicate an error.
		return;
	}

	const float	*sizes = sizeData.bytes;
		
	/// we never draw scans that are after the maxScan, as they have lower sizes than the maxScan.
	/// The curve would go back to the left and overlap itself
	int	maxScan = MIN(sample.maxScan, (int)nRecordedScans -1);
		
	/// the first scan for which me may draw the fluorescence is the before the startSize
	int	startScan = MIN(maxScan, MAX(sample.minScan, [sample scanForSize:startSize]-1));
		
	size_t maxPointsInCurve = 40;
	CGPoint *pointArray = NULL;
	
	/// On apple Silicon, curves are drawn using CGPath with 40-point-long subpaths.
	/// On intel and if we draw to screen, we will draw separate line segments, which is faster (but slower on Apple silicon)
	const BOOL useCGPath = appleSilicon || ![NSGraphicsContext currentContextDrawingToScreen];
	
	if(!useCGPath){
		if(pointsForPath) {
			free(pointsForPath);
		}
		maxPointsInCurve = (maxScan-startScan +2)*2;
		pointsForPath = malloc(maxPointsInCurve*sizeof(CGPoint));
		pointArray = pointsForPath;
	} else {
		CGPoint temp[40];
		pointArray = temp;
		CGPathRelease(path);
		path = CGPathCreateMutable();
	}
	
	/// We add the first point to draw to the array
	CGFloat lastX = (sizes[startScan] - leftOffset)*hScale;
	CGFloat y = fluo[startScan]*vScale;
	if (y < minY) {
		y = minY -1;
	}
	const int16_t lowerFluo = minY / vScale; 	/// to quickly evaluate if some scans should be drawn
		
	pointArray[0] = CGPointMake(lastX, y);
	pointCount = 1;
	BOOL outside = NO;			/// whether a scan is after maxSize. Used to determine when to stop drawing.
	int scan = startScan+1;
	
	while(!outside && scan <= maxScan) {
		float size = sizes[scan];
		if(size > endSize) {
			outside = YES;
		}
		CGFloat x = (size - leftOffset) * hScale;
		
		int16_t scanFluo = fluo[scan];
		if (scan < maxScan) {
			/// we may skip a point that is too close from previously drawn scans and not a local minimum / maximum
			/// or that is lower than the fluo threshold
			int16_t previousFluo = fluo[scan-1];
			int16_t nextFluo = fluo[scan+1];
			if((x-lastX < 1 && (previousFluo < scanFluo || nextFluo <= scanFluo) &&
				(previousFluo > scanFluo || nextFluo >= scanFluo)) || scanFluo < lowerFluo) {
				/// and that is not the first/last of a series of scans under the lower threshold
				if((scanFluo > lowerFluo || (previousFluo <= lowerFluo && nextFluo <= lowerFluo))) {
					/// We must draw the first point and the last point outside the dirty rect
					if(!outside) {
						scan++;
						continue;
					}
				}
			}
		}
		lastX = x;
		y = scanFluo * vScale;
		if (y < minY) {
			y = minY -1;
		}
		
		CGPoint point = CGPointMake(x, y);
		pointArray[pointCount++] = point;
		if((pointCount == maxPointsInCurve || outside || scan == maxScan)) {
			if(useCGPath) {
				CGPathAddLines(path, NULL, pointArray, pointCount);
				pointArray[0] = point; /// The first point of the next subpath is the last point of the previous one.
				pointCount = 1;
			}
		} else if(!useCGPath) {
			/// Here, each point is duplicated in the array because a segment ends where the next begins.
			pointArray[pointCount++] = point;
		}
		
		scan++;
	}
}



- (void)drawCrosstalkPeaksInContext:(CGContextRef)ctx FromSize:(float)startSize toSize:(float)endSize vScale:(float)vScale hScale:(float)hScale leftOffset:(float)leftOffset useRawData:(BOOL)useRawData maintainPeakHeights:(BOOL)maintainPeakHeights offScaleColors:(NSArray<NSColor *> *)offScaleColors {
	
	Chromatogram *sample = self.chromatogram;
	NSData *fluoData = useRawData? self.primitiveRawData : [self adjustedDataMaintainingPeakHeights:maintainPeakHeights];
	const int16_t *fluo = fluoData.bytes;
	long nRecordedScans = fluoData.length/sizeof(int16_t);

	NSData *sizeData = sample.sizes;
	const float	*sizes = sizeData.bytes;
		
	/// we never draw scans that are after the maxScan, as they have lower sizes than the maxScan.
	/// The curve would go back to the left and overlap itself
	int	maxScan = sample.maxScan;
	if(maxScan >= nRecordedScans) {
		maxScan = (int)nRecordedScans -1;
	}
		
	/// the first scan for which me may draw the fluorescence is the before the startSize
	int	startScan = [sample scanForSize:startSize]-1;
	if(startScan < sample.minScan) {
		/// but for the reason stated above, we don't draw scans before the minScan
		startScan = sample.minScan;
	}
	
	NSInteger colorCount = offScaleColors.count;
	const CGFloat lowerY = 1;
	NSColor *currentOffscaleColor;
	
	NSData *peakData = self.peaks;
	const Peak *peaks = peakData.bytes;
	NSInteger nPeaks = peakData.length / sizeof(Peak);
	for (int i = 0; i < nPeaks; i++) {
		const Peak *peakPTR = &peaks[i];
		int32_t endScan = peakEndScan(peakPTR);
		if(endScan >= startScan) {
			if(endScan >= maxScan) {
				break;
			}
			int peakStartScan = peakPTR->startScan;
			float peakStartSize = sizes[peakStartScan];
			if(peakStartSize <= endSize && peakStartScan < endScan) {
				int offScaleChannel = -(peakPTR->crossTalk + 1);
				if(offScaleChannel >= 0 && offScaleChannel <= colorCount) {
					CGFloat x = (peakStartSize- leftOffset)*hScale;
					CGFloat y = -1;
					CGPoint *pointArray = malloc((endScan - peakStartScan + 3) * sizeof(CGPoint));
					pointArray[0] = CGPointMake(x, y);
					int nPointsInPath = 1;
					
					for (int scan = peakStartScan; scan <= endScan; scan++) {
						x = (sizes[scan] - leftOffset) * hScale;
						y = fluo[scan] * vScale;
						if(y < lowerY) {
							y = lowerY -1;
						}
						pointArray[nPointsInPath++] = CGPointMake(x, y);
					}
					x = (sizes[endScan] - leftOffset) * hScale;
					pointArray[nPointsInPath++] = CGPointMake(x, -1);
					
					NSColor *color = offScaleColors[offScaleChannel];
					if(color !=currentOffscaleColor) {
						currentOffscaleColor = color;
						CGContextSetFillColorWithColor(ctx, color.CGColor);
					}
					CGContextBeginPath(ctx);
					CGContextAddLines(ctx, pointArray, nPointsInPath);
					free(pointArray);
					pointArray = NULL;
					CGContextClosePath(ctx);
					CGContextFillPath(ctx);
				}
			} else {
				break;
			}
		}
	}
}


- (void)drawInContext:(CGContextRef)ctx {
	if(path) {
		CGContextAddPath(ctx, path);
		CGContextStrokePath(ctx);
		CGPathRelease(path);
		path = NULL;
	} else if(pointsForPath && pointCount > 0) {
		CGContextStrokeLineSegments(ctx, pointsForPath, pointCount);
		free(pointsForPath);
		pointsForPath = NULL;
		pointCount = 0;
	}
}


#pragma mark - archiving/unarchiving

+(BOOL)supportsSecureCoding {
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[super encodeWithCoder:coder];
	[coder encodeObject:self.fragments forKey:@"fragments"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		self.fragments = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, LadderFragment.class, nil]  forKey:@"fragments"];
	}
	return self;
}

- (id)copy {
	Trace *copy = super.copy;
	if(copy.isLadder) {
		copy.fragments = [[NSSet alloc] initWithSet:self.fragments copyItems:YES];
	}
	return copy;
}


- (void)didTurnIntoFault {
		[super didTurnIntoFault];
		_adjustedData = nil;
		_adjustedDataMaintainingPeakHeights = nil;
		previousPeaks = nil;
		previousPeaksM = nil;
}


- (void)dealloc {
	CGPathRelease(path);
	if(pointsForPath) {
		free(pointsForPath);
	}
}

@end


