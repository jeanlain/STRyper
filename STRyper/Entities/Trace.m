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

@import Accelerate;

CodingObjectKey TraceIsLadderKey = @"isLadder",
TracePeaksKey = @"peaks",
TraceFragmentsKey = @"fragments";


@interface Trace ()
/// Fluorescence data (array of 16-bit integers) with baseline "noise" removed.
///
/// This attribute can be used to draw fluorescence curves in which peaks stand out more.
///
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



@implementation Trace

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
	[self findLadderFragmentsAndComputeSizing];
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
	int nPeaks = 0;
	/// we have several rounds of peak detection and baseline fluo removal.
	///  This is because we outline peaks on adjusted data (with baseline level subtracted) and because the subtraction is better after more than 1 round
	for(int round = 1; round <= 3; round++) {
		if(round == 1)	{
			nPeaks = peakDetect(raw, nScans, peaks, &maxFluoLevel, peakThreshold, ratio);
			[self setPrimitiveValue:@(maxFluoLevel) forKey:@"maxFluo"];
		}
		else {
			ratio = 0.5;
			nPeaks = peakDetect(adjusted, nScans, peaks, &maxFluoLevel, peakThreshold, ratio);
		}
		if(nPeaks == 0) {
			break;
		}
		if(round < 3) {
			///we remove noise and put result in the adjusted array. Some fluo levels may become negative, but the second round will mitigate that.
			subtractBaseline(raw, peaks, nPeaks, nScans, adjusted, false);
		}
	}
	
	if(nPeaks == 0) {
		free(peaks); free(adjusted);
		return;
	}
	
	/// we set the peaks. The current peak edges are not close enough from the tips, which isn't ideal for user interaction with peaks.
	/// we will use the closest scan to a peak that has fluorescence 0 (in adjusted data),
	/// even if there can be scans with negative fluo levels (as we don't show negative fluo on the curves)
	for (int n = 0; n < nPeaks; n++ ) {
		Peak peak = peaks[n];
		int32_t tipScan = peak.startScan + peak.scansToTip;
		int32_t i = tipScan;			/// we start at the peak apex, and will go left to find the start scan
		int32_t localMin = i;
		int16_t localMinFluo = adjusted[i];
		while (i > peak.startScan && adjusted[i] > 0 && i > 0) { /// we find the left-hand minimum
			i--;
			if(adjusted[i] < localMinFluo) {
				localMinFluo = adjusted[i];
				localMin = i;
			}
			if(adjusted[i] > localMinFluo*1.5) {
				/// if the fluo starts to increase again (50% higher than the last recorded min), we consider we have reach another peak
				i = localMin;
				break;
			}
		}
		peaks[n].startScan = i;
		peaks[n].scansToTip = tipScan - i;
		
		/// we do the same for the right-hand minimum
		i = tipScan;
		int32_t endScan = i + peak.scansFromTip;
		localMin = i;
		localMinFluo = adjusted[i];
		while (i < endScan && adjusted[i] > 0) {
			i++;
			if(adjusted[i] < localMinFluo) {
				localMinFluo = adjusted[i];
				localMin = i;
			}
			if(adjusted[i] > localMinFluo*1.5) {
				i = localMin;
				break;
			}
		}
		peaks[n].scansFromTip = i - tipScan;
	}
	
	[self managedObjectOriginal_setPeaks:[NSData dataWithBytes:peaks length:nPeaks*sizeof(Peak)]];
	free(peaks);
	free(adjusted);
}



- (NSData*)adjustedData {
	if(!_adjustedData) {
		_adjustedData = [self fluoDataWithSubtractedBaselineMaintainingPeakHeight:NO];
	}
	return _adjustedData;
}


- (NSData *)adjustedDataMaintainingPeakHeights {
	if(!_adjustedDataMaintainingPeakHeights) {
		_adjustedDataMaintainingPeakHeights = [self fluoDataWithSubtractedBaselineMaintainingPeakHeight:YES];
	}
	return _adjustedDataMaintainingPeakHeights;
}


- (NSData *)fluoDataWithSubtractedBaselineMaintainingPeakHeight:(BOOL)maintainPeakHeights {
	NSData *fluoData =  self.primitiveRawData;
	if(!fluoData) {
		return nil;
	}
	if(self.peaks) {
		int nScans = (int)fluoData.length / sizeof(int16_t);
		const int16_t *raw = fluoData.bytes;
		int nPeaks = (int)self.peaks.length / sizeof(Peak);
		if(nPeaks == 0) {
			return fluoData;
		}
		int16_t *adjusted = malloc(nScans * sizeof(int16_t));
		NSData *peakData = self.peaks;
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
///   - maxFluo: On output, the maximum value of `fluo`.
///   - fluoThreshold: The minimum fluorescence value to consider a peak = the peak minimum height.
///   - minRatio: The minimum ratio of heights of the peak tip over the background, to consider a peak
int peakDetect (const int16_t *fluo, int nScans, Peak *peaks, int *maxFluo, int16_t fluoThreshold, float minRatio) {
	
	/// A scan is considered a peak tip if its fluo is higher than the threshold and its elevation is at least 1/minRatio higher than both local minima around it
	/// for each peak, we have two minima (both sides), but a minimum is shared between adjacent peaks
	int16_t minLocalFluo = SHRT_MAX;
	int16_t maxLocalFluo = 0; int32_t currentMinScan = 0; int32_t currentMaxScan = 0;
	int nPeaks = 0;
	for (int32_t scan = 0; scan < nScans; scan++) {
		int16_t f = fluo[scan];
		
		/// We assume we have passed a peak if the current min fluo level is sufficiently less than the current max,
		/// and same for the current fluo (which may not be a local minimum).
		/// This condition is met in the "descending" slope of the peak (at its right)
		if ((maxLocalFluo >= fluoThreshold) && (f < maxLocalFluo * minRatio) && (minLocalFluo < maxLocalFluo * minRatio) && (currentMinScan < currentMaxScan)) {
			peaks[nPeaks].crossTalk = 0;
			peaks[nPeaks].startScan = currentMinScan;
			
			/// we record the scan of the passed peak and of the last min
			peaks[nPeaks].scansToTip = currentMaxScan - currentMinScan;
			if(nPeaks > 0) {
				peaks[nPeaks-1].scansFromTip = currentMinScan - peaks[nPeaks-1].startScan - peaks[nPeaks-1].scansToTip;
			}
			currentMinScan = scan;					/// in case the current scan just happens to be the minimum between two peaks
			minLocalFluo = f; maxLocalFluo = f;		/// we reset the max and min fluo levels
			nPeaks++;
		}
		
		if (f < minLocalFluo) {
			minLocalFluo = f;
			currentMinScan = scan;
			if(currentMinScan > currentMaxScan) {
				/// as long as we are one the "descending slope" of the peak, we make sure the max local fluo is not taken from this region
				/// (and will be used when the fluo increases again)
				maxLocalFluo = f;
				currentMaxScan = scan;
			}
		} else if (f > maxLocalFluo) {
			maxLocalFluo = f;
			currentMaxScan = scan;
			if(*maxFluo < f) *maxFluo = f;		/// we also record the max fluo of the trace, which we will store later
		}
	}
	/// We close the last peak
	if(nPeaks > 0) {
		peaks[nPeaks-1].scansFromTip = currentMinScan - peaks[nPeaks-1].startScan - peaks[nPeaks-1].scansToTip;
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
	/// this can lead to negative fluo for scan that initially have positive fluorescence values. On the curve, these points will show at fluo zero (see TraceView's drawRect:).
	
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
				int firstScan = peak.startScan < overlappingPeakStart ? peak.startScan : overlappingPeakStart;
				int lastScan = endScan > overlappingPeakEnd ? endScan : overlappingPeakEnd;
				
				/// We try to reduce the influence of baseline level by subtracting the height at the first scan fo each peak.
				int16_t startFluo = fluo[peak.startScan];
				int16_t startFluoOvPeak = otherTraceFluo[overlappingPeakStart];
				/// To compare peak, we will reduce the height of the taller peak using this ratio.
				float heightRatio = (peakTipFluo - startFluo) / (sourcePeakTipFluo - startFluoOvPeak);
				float offset = 0, offset2 = 0; /// Indices that indicate how much peaks are aligned
				float combinedAreas = 0, addedAreas = 0;	/// Union and addition of peak areas.
				for (int k = firstScan; k <= lastScan; k++) {
					float currentPeakHeight = fluo[k] > startFluo? fluo[k] - startFluo : 0;
					float currentOverlappingPeakHeight = otherTraceFluo[k] > startFluoOvPeak? (otherTraceFluo[k] - startFluoOvPeak) * heightRatio : 0;
					combinedAreas += currentPeakHeight > currentOverlappingPeakHeight ? currentPeakHeight : currentOverlappingPeakHeight;
					addedAreas += currentPeakHeight + currentOverlappingPeakHeight;

					float diffHeight = currentPeakHeight - currentOverlappingPeakHeight;
					/// If we are past the tip of each peak, we change the sign of the difference in height.
					/// This is quite sensitive to the alignment of both peaks.
					offset += k < scan ? diffHeight : -diffHeight;
					offset2 += k < overlappingPeakTip ? diffHeight : -diffHeight;
				}
				float ratio = (addedAreas - combinedAreas) / combinedAreas; /// The percentage of the intersection of peak areas over total area.
																			/// It must not be too low
				if(ratio > 0.3 && fabs(offset)/combinedAreas < 0.3 && fabs(offset2)/combinedAreas < 0.3) {
					peak.crossTalk = -otherTrace.channel -1;
					/// We check if intense peaks in this other channel also induce crosstalk.
					/// If they don't, we conclude that the current peak doesn't results from crosstalk.
				
					int regionIndex = 0;
					for (int i = 0; i < numPeaks; i++) {
						const Peak *tracePeak = &tracePeaks[i];
						int peakScan = tracePeak->startScan + tracePeak->scansToTip;
						float heightRatio = otherTraceFluo[peakScan] / sourcePeakTipFluo;
						if(heightRatio >= 1 && fluo[peakScan] < peakTipFluo * heightRatio/2) {
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
								int leftScan = region->startScan > 0? region->startScan-1 : 0;
								if(heightRatio >= 1 && fluo[leftScan] < peakTipFluo * heightRatio/2) {
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
	[self resetAdjustedData];
	
	free(newPeaks);
	return YES;
	
}


-(void)resetAdjustedData {
	_adjustedData = nil;
	_adjustedDataMaintainingPeakHeights = nil;
	/// As -adjustedData is not a core data attribute, the adjusted data must be recomputed upon undo/redo
	NSUndoManager *undoManager = self.managedObjectContext.undoManager;
	if(undoManager.canUndo || undoManager.canRedo) {
		[undoManager registerUndoWithTarget:self selector:@selector(resetAdjustedData) object:nil];
	}
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


#pragma mark - ladderFragment creation

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
	NSData *rawData = trace.rawData;
	const int16_t *fluo = rawData.bytes;
	long nScans = rawData.length/sizeof(int16_t);
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
	
} LadderSize;



- (void)findLadderFragmentsAndComputeSizing {
	if(!self.isLadder) {
		return;
	}
	
	Chromatogram *sample = self.chromatogram;
	SizeStandard *sizeStandard = sample.sizeStandard;
	if(!sizeStandard) {
		return;
	}
	
	int nSizes = (int)sizeStandard.sizes.count;
	if(nSizes < 4){
		/// this should not happen in principle, as we enforce at least 4 sizes per size standard
		/// but if there are fewer, we remove all ladder fragments
		
		self.fragments = NSSet.new;
		/// we still size the sample to get "dummy" sizing parameters, otherwise the sample cannot be displayed
		[sample setLinearCoefsForReadLength:DefaultReadLength];
		return;
	}
	
	/// we retrieve the sizes of fragments in the size standard in ascending order to create an array of LadderSize struct
	NSArray *sortedFragments = [sizeStandard.sizes.allObjects sortedArrayUsingKey:@"size" ascending:YES];
	
	LadderSize ladderSizes[nSizes];									/// we use a variable-length array for this, as nSizes will never be very large
	int i = 0;
	for(SizeStandardSize *fragment in sortedFragments) {
		LadderSize size = {.size = (float)fragment.size, .ladderPeakPTR = NULL};
		ladderSizes[i++] = size;
	}
	
	NSData *peakData = self.peaks;
	int nPeaks = (int)peakData.length/sizeof(Peak);  			/// number of peaks in the ladder.
	
	if (nPeaks < self.fragments.count /3 || nPeaks < 3) {
		/// if we don't have enough peaks, we don't assign them
		/// we still create ladder fragments, which will have no scan but can still assigned manually on a traceView
		[self setLadderFragmentsWithSizes:ladderSizes nSizes:nSizes];
		[sample setLinearCoefsForReadLength:ladderSizes[nSizes-1].size + 50.0];
		return;
	}
	
	LadderPeak ladderPeaks[nPeaks]; 	/// Array of LadderPeak structs based on the peaks of the trace

	/// to select among competing peaks later on, we also record the mean height and area of peaks that presumably represent the ladder, excluding artifacts.
	/// for height, we need to access the fluorescence level
	float heights[nPeaks];									/// as we will store peaks by decreasing sizes, we will store heights in this array
	vDSP_Length nHeights = 0;
	
	float meanHeight = 0;
	int n = 0, sumHeight = 0;
	const Peak *peaks = peakData.bytes;
	
	for (int i = nPeaks-1; i >= 0; i--) {
		/// we enumerate peaks from last to first (in scan number), as the first peaks are usually artifacts
		n++;
		const Peak *peakPTR = &peaks[i];
		LadderPeak newLadderPeak = LadderPeakFromPeak(peakPTR, self);
		sumHeight += newLadderPeak.height;
		meanHeight = sumHeight/n;
		/// we ignore peaks that are much higher than the current average and are near the start of trace
		if(peakPTR->crossTalk >= 0 && !(newLadderPeak.height > meanHeight *2 && peakEndScan(peakPTR) < sample.nScans/3)) {
			heights[nHeights] = newLadderPeak.height;
			nHeights++;
		}
		ladderPeaks[i] = newLadderPeak;
	}
	
	vDSP_vsort(heights, nHeights, -1);
	n = 0; sumHeight = 0;
	float minHeight = heights[nHeights-1];		/// the minimum height of the peaks that probably correspond to the ladder (those we use to compute meanHeight)
	
	for (int i = 1; i < nHeights; i++) {
		if(n == nSizes || (i < nHeights -1 && i > 2 && heights[i] > 3 * heights[i+1])) {
			break;		/// We stop considering peaks if a peak is much shorter than the previous one. This helps to exclude noise.
						/// Also, we stop when we have reached the number of expected ladder fragments
		}
		sumHeight += heights[i];
		minHeight = heights[i];
		n++;
	}
	
	if(n == 0) {
		[self setLadderFragmentsWithSizes:ladderSizes nSizes:nSizes];;
		[sample setLinearCoefsForReadLength:ladderSizes[nSizes-1].size + 50.0];
		return;
	}
	meanHeight = sumHeight/n;
	
	LadderPeak *ladderPeakPTRs[nPeaks];  	/// Pointers to the peaks that will be used for the sizing.
	n = 0;
	
	for (int i = 0; i < nPeaks; i++) {
		LadderPeak *ladderPeakPTR = &ladderPeaks[i];
		if(ladderPeakPTR->height*2 >= minHeight && ladderPeakPTR->crossTalk >= 0) {
			/// We ignore peaks resulting from crosstalk although the code afterwards still checks for crosstalk for peak selection,
			/// as we previously were still considering crosstalk peaks.I left these checks in the code in case we need them.
			/// A peak resulting from crosstalk could be valid if a ladder fragment has the same size as a fragment in another channel.
			/// But currently, this peak is ignored. I believe it is safer to let the user assign it manually.
			ladderPeakPTRs[n] = ladderPeakPTR;
			n++;
		}
	}
	
	if (n < 3) {
		[self setLadderFragmentsWithSizes:ladderSizes nSizes:nSizes];
		[sample setLinearCoefsForReadLength:ladderSizes[nSizes-1].size + 50.0];
		return;
	}
	
	int nRetainedPeaks = n;
	
	/// We assign the first peak (in scan number) to the first size, the last peak to the last size.
	/// Using a 2-point line obtained from this assignment, we assign other intermediate peaks to intermediate sizes (based on proximity).
	/// We then measure the offset between assigned sizes and peak positions (deduced from the slope of the line) as a sizing quality score
	/// We reiterate this by incrementing the first peak and decrementing the last peak, in case they were wrong (very common for first peaks, due to artifact at the start of the trace).
	/// We also decrement the last size to assign, which may be missing (electrophoresis might have stopped too soon and the longer fragments may be missing).
	
	int minNSizes = 0; 					/// minimum number of assigned sizes to consider the results
	const float threshold = 100; 		/// threshold for good quality score (see how we compute it below)
	
	
	LadderPeak assignedPeaks[nSizes];											/// the LadderPeaks that are assigned to ladder sizes in the current iteration
	NSData *assignments[nSizes +1];												/// the above array will be copied in an NSData and stored in this array at an index corresponding to the number assigned sizes.
	float bestScores[nSizes+1];													/// the best quality score for a given number of sizes assigned (this number is the index of the array, hence the +1)
	float fill = 0;
	vDSP_vfill(&fill, bestScores, 1, nSizes+1);
	
	for (int last = nRetainedPeaks-1; last+1 >= minNSizes; last--) {		  		  	/// decrementing last peak index
		for (int lastSize = nSizes-1; lastSize+1 >= minNSizes; lastSize--) {  	/// decrementing last size index
			LadderPeak *lastPeakPTR = ladderPeakPTRs[last];
			lastPeakPTR->size = ladderSizes[lastSize].size;
			for (int first = 0; last - first +1 >= minNSizes; first++) {	  	/// incrementing first peak index
				LadderPeak *firstPeakPTR = ladderPeakPTRs[first];
				/// we compute the slope and intercept of the line passing through the first and last peak (x = scan number, y = size)
				float slope = (lastPeakPTR->size - firstPeakPTR->size) / (lastPeakPTR->scan - firstPeakPTR->scan);
				float intercept = (lastPeakPTR->size + firstPeakPTR->size)/2 - slope * (lastPeakPTR->scan + firstPeakPTR->scan)/2;
				
				/// we define a local slope and intercept, which we will use to predict the location of a ladder fragment
				/// (the relationship with size and scan may not be linear)
				/// we initialize them with the parameters based on the first and last peaks
				float localSlope = slope;
				float localIntercept = intercept;
				/// these parameters will then be based on two adjacent ladder fragments assigned to two sizes
				int rightAssignedSize = lastSize;
				int leftAssignedSize = lastSize;
				
				for (int i = 0; i < nSizes; i++) {
					/// for this, we must deassign all intermediate sizes that were assigned in previous iterations
					ladderSizes[i].ladderPeakPTR = NULL;
				}
				ladderSizes[lastSize].ladderPeakPTR = lastPeakPTR;
				
				
				int sizeIndex = lastSize-1;		/// the index of the size the peak will be assigned to
				
				/// we assign peaks to sizes from right to left. This is because the left part of the trace often contains noise
				for(int i = last-1; i >= 0; i--) {
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
							if(j == leftAssignedSize -1 && leftAssignedSize != lastSize) {
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
					/// if the peak is assigned, we compute the local slope and intercept based on the peaks assigned to this size and to the previous size										}
					if(assigned && 	fabsf(ladderPeakPTR->offset) < 30)  {
						if(sizeIndex < leftAssignedSize) {
							rightAssignedSize = leftAssignedSize;
							leftAssignedSize = sizeIndex;
						}
						LadderPeak leftPeak = *ladderPeakPTR;
						LadderPeak rightPeak = *ladderSizes[rightAssignedSize].ladderPeakPTR;
						
						localSlope = (rightPeak.size - leftPeak.size) / (rightPeak.scan - leftPeak.scan);
						localIntercept = (rightPeak.size + leftPeak.size)/2 - localSlope * (rightPeak.scan + leftPeak.scan)/2;
					}
				}
				
				/// we store assigned peaks in the designated array
				int nAssigned = 0, nMissed = 0;
				for (int i = first; i < nRetainedPeaks; i++) {
					LadderPeak *ladderPeakPTR = ladderPeakPTRs[i];
					if(ladderPeakPTR->size >= 0 && i <= last) {
						assignedPeaks[nAssigned] = *ladderPeakPTR;
						nAssigned++;
					} else if(ladderPeakPTR->height > minHeight && ladderPeakPTR->crossTalk >= 0) {
						/// if a peak has a good height and has no size assigned (or is beyond the last peak),
						/// we consider that the assigned to the size has been missed
						nMissed++;
					}
				}
				if(nMissed > nSizes - nAssigned) {
					nMissed = nSizes - nAssigned;
				}
				
				if(nAssigned < minNSizes) {
					continue;
				}
				/// we compute the sizing quality score. It is based on a regression line computed with all assigned peaks (not just the first and last, this time)
				slope = regressionForPeaks(assignedPeaks, nAssigned, 0, &intercept);
				for (int i = 0; i < nAssigned; i++) {
					assignedPeaks[i].offset = assignedPeaks[i].size -  (slope*assignedPeaks[i].scan + intercept);
				}
				
				float meanOffset = 0.0;
				for (int i = 0; i < nAssigned -1; i++) {
					/// the score is based on the difference of offset between successive peaks, considering their distance (in scans)
					/// two peaks that are close must have similar offsets, otherwise it means a peak has not be properly assigned
					meanOffset += fabs(assignedPeaks[i].offset - assignedPeaks[i+1].offset) / abs(assignedPeaks[i].scan - assignedPeaks[i+1].scan);
				}
				
				meanOffset /= (nAssigned-1);
				float r = 1/meanOffset * (nAssigned - nMissed)/nAssigned;
				
				if(r > bestScores[nAssigned]) {		/// if the fit is better than the best so far, for a this number of assigned fragments
					bestScores[nAssigned] = r;
					/// we add results to the array
					assignments[nAssigned] = [NSData dataWithBytes:ladderSizes length:nSizes*sizeof(LadderSize)];
					
				}
				
				if(r >= threshold) {				/// if we consider that the assignment is good enough, we won't look for iterations involving a lower number of sizes
					minNSizes = nAssigned;
				}
			}
		}
	}
	
	
	NSData *bestAssignment = assignments[nSizes];		/// by default, we keep results from the largest number of sizes;
	float topScore = 0;
	int nAssignedSizes;
	for (nAssignedSizes = nSizes; nAssignedSizes >= minNSizes; nAssignedSizes--) {
		if(bestScores[nAssignedSizes] >= threshold) {
			bestAssignment = assignments[nAssignedSizes];
			break;
		} else {
			if(bestScores[nAssignedSizes] * nAssignedSizes/nSizes > topScore) {
				topScore = bestScores[nAssignedSizes] * nAssignedSizes/nSizes;
				bestAssignment = assignments[nAssignedSizes];;
			}
		}
	}
	
	const LadderSize *assigned = bestAssignment.bytes;
		
	[self setLadderFragmentsWithSizes:assigned nSizes:nSizes];
	
	[sample computeFitting];
}


/// Tries to assign a ladder peak to a size and returns whether the assignment was made.
///
/// Depending on the `ladderPeakPTR` member of `ladderSizePTR`,
/// the method may not replace it by `candidatePeakPTR` (if this peak appear less suited) and may return `NO`.
/// - Parameters:
///   - candidatePeakPTR: Pointer to the peak to assign to the size.
///   - ladderSizePTR: Pointer to the size that may be assigned to the peak pointed by `candidatePeakPTR`.
///   - meanHeight: A mean value of peak height that is used to asses peak quality.
BOOL assignPeakToSize(LadderPeak  *candidatePeakPTR, LadderSize *ladderSizePTR, float meanHeight) {
	candidatePeakPTR->size = -1;				/// we deassign the peak
	if(fabs(candidatePeakPTR->offset) > 15) {
		/// if the peak offset is just too large, we cannot assign it
		return NO;
	}
	/// we check if a previously inspected peak is assigned to this size
	if(ladderSizePTR->ladderPeakPTR != NULL) {
		LadderPeak candidate = *candidatePeakPTR;
		/// in that case, the candidate may replace the resident for this size
		LadderPeak resident = *ladderSizePTR->ladderPeakPTR;
		/// we use the "shape" of the peaks, which represents their flatness (area/height). A peak that is too flat may represent an artifact.
		
		float residentShape = (float)resident.area / resident.height;
		float candidateShape = (float)candidate.area / candidate.height;
		bool replace = false ;				/// will be true if the resident peak needs to be replaced by the candidate
		bool closer = fabs(candidate.offset) < fabs(resident.offset);
		bool crossTalk = candidate.crossTalk < 0;
		if(resident.crossTalk < 0) {
			if(!crossTalk || closer) {
				/// this is the case if the resident is crosstalk and the candidate isn't or is closer
				replace = true;
			}
		} else if(residentShape > candidateShape*3 && resident.height < meanHeight/2) {
			/// if the resident peak isn't crosstalk, but is too flat or too short
			if(!crossTalk && ((candidateShape <= residentShape*3 && candidate.height >= meanHeight/3) || closer)) {
				replace = true;				/// the candidate replaces it doesn't have these defects, or is closer
			}
		} else if(!crossTalk && candidateShape <= residentShape*3 && candidate.height >= meanHeight/3 && closer) {
			replace = true;					/// else the candidate must have no defect, no crosstalk and be closer
		}
		if(replace) {
			/// if the resident is replaced, we de-assign it
			ladderSizePTR->ladderPeakPTR->size = -1;
		} else {
			return NO;
		}
	}
	ladderSizePTR->ladderPeakPTR = candidatePeakPTR;
	candidatePeakPTR->size = ladderSizePTR->size;
	return YES;
	
}

/// returns slope between scan and size of peaks using ordinary least squares
float regressionForPeaks (const LadderPeak *peaks, int nPeaks, int first, float *intercept) {
	float sumXX=0, sumXY=0, sumX=0, sumY=0, slope;
	for (int i = first; i < nPeaks+first; i++) {
		sumXX += peaks[i].scan * peaks[i].scan;
		sumX += peaks[i].scan;
		sumY += peaks[i].size;
		sumXY += peaks[i].scan * peaks[i].size;
	}
	slope= (nPeaks*sumXY - sumX*sumY)/(nPeaks*sumXX - pow(sumX, 2));
	*intercept = (sumY - slope*sumX)/nPeaks;
	return slope;
}


/// Sets our -fragments attribute to match the LadderSizes given in the sizes array.
///
/// nSizes is the number of sizes to consider.
///
/// This method does not check if we are a ladder.
- (void)setLadderFragmentsWithSizes:(const LadderSize *)sizes nSizes:(NSUInteger)nSizes {
	NSUInteger nFragments = self.fragments.count;
	if(nFragments < nSizes) {
		NSSet *ladderFragments = NSSet.new;
		for (NSUInteger i = nFragments; i < nSizes; i++) {
			LadderFragment *fragment = [[LadderFragment alloc] initWithEntity:LadderFragment.entity insertIntoManagedObjectContext:self.managedObjectContext];
			ladderFragments = [ladderFragments setByAddingObject:fragment];
		}
		[self addFragments:ladderFragments];
	}
	
	NSUInteger i = 0;
	NSMutableSet *fragmentsToRemove = NSMutableSet.new;
	for(LadderFragment *fragment in self.fragments) {
		if(i < nSizes) {
			LadderSize size = sizes[i];
			if(size.ladderPeakPTR != NULL) {
				fragment.scan = size.ladderPeakPTR->scan;
			} else {
				fragment.scan = 0;
			}
			fragment.size = size.size;
		} else {
			[fragmentsToRemove addObject:fragment];
		}
		i++;
	}
	
	[self removeFragments:fragmentsToRemove];	/// we remove superfluous fragments in one command as our fragments property is observed
	
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

@end


