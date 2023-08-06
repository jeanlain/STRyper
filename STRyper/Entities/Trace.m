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

@import Accelerate;

NSString * _Nonnull const TraceIsLadderKey = @"isLadder";
NSString * _Nonnull const TracePeaksKey = @"peaks";
NSString * _Nonnull const TraceFragmentsKey = @"fragments";


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


int32_t peakEndScan(Peak peak) {
	return peak.startScan + peak.scansToTip + peak.scansFromTip;
}


- (void)setPeakThreshold:(int16_t)peakThreshold {
	if(peakThreshold < 10) {
		peakThreshold = 10;
	}
	[self managedObjectOriginal_setPeakThreshold:peakThreshold];
	[self findPeaks];
	
	/// as we may have found new peaks, we look for new ladder fragments
	[self findLadderFragmentsAndComputeSizing];
	
	[self.managedObjectContext.undoManager setActionName:@"Change peak detection threshold"];
}


- (void)findPeaks {
	int nScans = (int)self.rawData.length / sizeof(int16_t);
	int16_t peakThreshold = self.peakThreshold;
	float ratio = 0.7;  							/// ratio of minimum fluo next to peak / peak height.
	int maxFluoLevel = 0;   						/// the max fluo level of a trace
	const int16_t *raw = self.rawData.bytes;
	
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
	
	[self setCrossTalk];
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
		const Peak *peaks = self.peaks.bytes;
		
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
		Peak peak = peaks[i];
		int start = peak.startScan;
		end = peakEndScan(peak);
		if(start - previousMin > 0) {
			/// we are between peaks
			subtractBaselineInRange(rawData, outputData, previousMin, start, -1);
		}
		if(end - start > 0) {
			///we are within a peak.
			///If we should not preserve its height, we specify a negative peak height, which is ignored in subtractBaselineInRange().
			int16_t peakHeight = maintainPeakHeights? rawData[start + peak.scansToTip] : -1;
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



/// Sets the crossTalk member of each peak (from the -peaks attribute) by checking whether it is in an offscale region
/// and, if not in an offscale region, by comparing the fluorescence data in other traces
- (void)setCrossTalk {
	if(self.peaks.length == 0 || self.chromatogram.offscaleRegions.length == 0) {
		return;
	}
	long nPeaks = self.peaks.length/sizeof(Peak);
	if(nPeaks == 0) {
		return;
	}
	
	const Peak *peaks = self.peaks.bytes;
	
	const OffscaleRegion *regions = self.chromatogram.offscaleRegions.bytes;
	long nOffscale = self.chromatogram.offscaleRegions.length/sizeof(OffscaleRegion);
	if(nOffscale == 0) {
		return;
	}
	
	const int16_t *fluo = self.rawData.bytes;
	long nScans = self.rawData.length/sizeof(int16_t);
	Peak *newPeaks = malloc(nPeaks * sizeof(*newPeaks));	/// will contain the peaks with crosstalk information
	NSSet *traces = self.chromatogram.traces;	/// if we need to check fluorescence data in other traces;
	
	int j = 0;		/// the index of the off-scale region
	for (int i = 0; i < nPeaks; i++) {
		Peak peak = peaks[i];
		peak.crossTalk = 0;
		int scan = peak.startScan + peak.scansToTip;
		/// we check if the peak's tip is within an saturated region
		
		while(scan > regions[j].startScan + regions[j].regionWidth -1 && j < nOffscale-1) {
			j++;
		}
		OffscaleRegion region = regions[j];
		if(scan >= region.startScan && scan < region.startScan + region.regionWidth) {
			/// if it is, we get the saturated channel is the same of the trace
			if(region.channel == self.channel) {
				/// if the peak has saturated the camera, we record the width of the saturated area,
				/// which can be used to determine the size of the peak (as saturation leads to clipping). The larger the area, the bigger the peak.
				peak.crossTalk = region.regionWidth;
			} else {
				/// If there the saturated region results from another channel at the peak, we check if the peak results from crosstalk.
				/// To do so, we compare the fluorescence at the peak to the fluo levels at the borders of the saturated region.
				/// If the peak height is more than twice that at both edges, we consider that the peak results from crosstalk
				
				int16_t leftFLuo = region.startScan > 0? fluo[region.startScan-1] : fluo[0];
				int regionEndScan = region.startScan + region.regionWidth;
				int16_t rightFluo = regionEndScan < nScans? fluo[regionEndScan] : fluo[regionEndScan-1];
				
				if(leftFLuo < fluo[scan] /2 && rightFluo < fluo[scan] / 2) {
					/// for a peak resulting from crosstalk (saturation of another channel), we record the opposite of the width
					peak.crossTalk = -region.regionWidth;
				}
			}
		}
		
		if (peak.crossTalk == 0 && fluo[scan] < SHRT_MAX / 4) {
			/// if the peak has not been considered crosstalk based on this criterion and is not too high, we check data from other traces
			int16_t maxFluo = 0;
			int endScan = peakEndScan(peak);
			Trace *otherTrace;
			for(Trace *trace in traces) {
				/// We get the max fluo level across other traces
				if(trace != self) {
					NSData *traceData = trace.primitiveRawData;
					if(traceData.length/sizeof(int16_t) >= endScan) {
						const int16_t *data = traceData.bytes;
						int16_t rawFluo = data[scan];
						if(rawFluo > maxFluo) {
							maxFluo = rawFluo;
							otherTrace = trace;
						}
					}
				}
			}
			
			if(maxFluo > fluo[scan]*4 && otherTrace) {
				/// If the fluorescence in another channel is higher than that of the peak,
				/// we evaluate if the fluorescence curves of both channel look similar in the peak area
				/// For this, we need to standardize for the difference in peak height.
				
				const int16_t* rawData = otherTrace.primitiveRawData.bytes;
				const Peak *tracePeaks = otherTrace.peaks.bytes;
				long numPeaks = otherTrace.peaks.length / sizeof(Peak);

				float tipFluo = maxFluo;
				for (int k = peak.startScan; k <= endScan; k++) {
					int16_t otherChannelFluo = rawData[k];
					if(otherChannelFluo > tipFluo) {
						tipFluo = otherChannelFluo;
					}
				}
				float heightRatio = fluo[scan] / tipFluo;
				/// We then compute an index of difference in fluo levels
				/// which is the difference in fluo levels relative to the peak elevation
				int16_t peakElevation = fluo[scan] - fluo[peak.startScan];
				float delta = 0;
				for (int k = peak.startScan; k <= endScan; k++) {
					delta += (fluo[k] - rawData[k] * heightRatio)/peakElevation;
				}
				delta /= endScan - peak.startScan +1; /// we compute its average
				
				if(fabs(delta) < 0.3) {
					/// if the average difference in standardized fluo is less than 30%, we consider that the peak may result from crosstalk
					peak.crossTalk = -1;

					/// But to make sure of this, we check if peaks in the other channel also induce peaks in this trace with similar ratios in height
					bool notCrosstalk = false;
					int regionIndex = 0;	///index of offscale region that we use later
					
					for (int i = 0; i < numPeaks; i++) {
						Peak tracePeak = tracePeaks[i];
						int peakScan = tracePeak.startScan + tracePeak.scansToTip;
						int16_t otherChannelFluo = rawData[peakScan];
						int16_t thisChannelFluo = fluo[peakScan];
						if(otherChannelFluo > 1000 && thisChannelFluo <= 0) {
							notCrosstalk = true;
						} else {
							float ratio =  thisChannelFluo / otherChannelFluo;
							if(otherChannelFluo > 1000 && ratio > heightRatio * 2) {
								/// if a peak with sufficient height has a height ratio that is much lower than the reference ratio,
								/// the current peak may not be due to crosstalk
								notCrosstalk = true;
							}
						}
						if(notCrosstalk) {
							/// we check if the peak that has not caused crosstalk is in an offscale region.
							/// Because if it is, the height ratio is not reliable
							while(peakScan > regions[regionIndex].startScan + regions[regionIndex].regionWidth -1 && regionIndex < nOffscale-1) {
								regionIndex++;
							}
							OffscaleRegion region = regions[regionIndex];
							if(peakScan < region.startScan | peakScan > region.startScan + region.regionWidth) {
								/// if the peak that did not induce crosstalk is not in an offscale region,
								/// we consider that the peak under consideration does not result from crosstalk
								peak.crossTalk = 0;
								break;
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
	const int16_t *fluo = useRawData? self.primitiveRawData.bytes : self.adjustedData.bytes;
	
	/// To look for a peak, we must know where the scan is with respect to other peaks.
	const Peak* peaks = self.peaks.bytes;
	long nPeaks = self.peaks.length/sizeof(Peak);
	
	/// We record the end of the closest peak on the left, and the start of the closest peak on the right
	int leftEnd = 0;
	int rightStart = self.chromatogram.nScans;
	
	for(int n = 0; n < nPeaks-1; n++) {
		int startScan = peaks[n].startScan;
		int endScan = peakEndScan(peaks[n]);
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
	
	const Peak *peaks = self.peaks.bytes;
	long nPeaks = self.peaks.length / sizeof(Peak);
	Peak *newPeaks = malloc((nPeaks+1)*sizeof(*newPeaks));	/// We recreate the peak array with the newPeak inserted
	
	int inserted = 0;
	/// We insert the newPeak at the correct position as the peaks must be sorted by ascending scan number
	for (int i = 0; i <= nPeaks; i++) {
		if(inserted == 0 && (i == nPeaks || peaks[i].startScan + peaks[i].scansToTip > tipScan)) {
			/// We insert the peak once we detect the current peak would be at a lower scan or if we have reached the end
			/// We check if there is room for the new peak. It must not overlap surrounding peaks.
			if((i > 0 && peakEndScan(peaks[i-1]) > newPeak.startScan) || (i < nPeaks && peaks[i].startScan < peakEndScan(newPeak)) ) {
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
	int crossTalk;					/// see equivalent property in Peak struct
	
} LadderPeak;



LadderPeak LadderPeakFromPeak(Peak peak, Trace *trace) {
	LadderPeak ladderPeak;
	ladderPeak.scan = peak.startScan + peak.scansToTip;
	ladderPeak.width = peakEndScan(peak) - peak.startScan;
	const int16_t *fluo = trace.rawData.bytes;
	ladderPeak.area = 0;
	int endScan = peakEndScan(peak);
	for(int scan = peak.startScan; scan <= endScan; scan++) {
		ladderPeak.area += fluo[scan];
	}
	ladderPeak.height = fluo[ladderPeak.scan];
	ladderPeak.crossTalk = peak.crossTalk;
	ladderPeak.size = -1.0;
	ladderPeak.offset = 0.0;
	return ladderPeak;
}


typedef struct LadderSize {			/// describes a size in a size standard
	float size;						/// in base pairs
	LadderPeak *peak;				/// pointer to the LadderPeak assigned to this size
	
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
	NSArray *sortedFragments = [sizeStandard.sizes.allObjects sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"size" ascending:YES]]];
	
	LadderSize ladderSizes[nSizes];									/// we use a variable-length array for this, as nSizes will never be very large
	int i = 0;
	for(SizeStandardSize *fragment in sortedFragments) {
		LadderSize size = {.size = (float)fragment.size, .peak = NULL};
		ladderSizes[i++] = size;
	}
	
	/// we create an array of LadderPeak structs based on the peaks of the trace
	int nPeaks = (int)self.peaks.length/sizeof(Peak);  			/// number of peaks in the ladder.
	LadderPeak ladderPeaks[nPeaks];
	
	if (nPeaks < self.fragments.count /3 || nPeaks < 3) {
		/// if we don't have enough peaks, we don't assign them
		/// we still create ladder fragments, which will have no scan but can still assigned manually on a traceView
		[self setLadderFragmentsWithSizes:ladderSizes nSizes:nSizes];
		[sample setLinearCoefsForReadLength:ladderSizes[nSizes-1].size + 50.0];
		return;
	}
	
	/// to select among competing peaks later on, we also record the mean height and area of peaks that presumably represent the ladder, excluding artifacts.
	/// for height, we need to access the fluorescence level
	float heights[nPeaks];									/// as we will store peaks by decreasing sizes, we will store heights in this array
	vDSP_Length nHeights = 0;
	
	float meanHeight = 0;
	int n = 0, sumHeight = 0;
	const Peak *peaks = self.peaks.bytes;
	for (int i = nPeaks-1; i >= 0; i--) {
		/// we enumerate peaks from last to first (in scan number), as the first peaks are usually artifacts
		n++;
		Peak peak = peaks[i];
		ladderPeaks[i] = LadderPeakFromPeak(peak, self);
		sumHeight += ladderPeaks[i].height;
		meanHeight = sumHeight/n;
		/// we ignore peaks that are much higher than the current average and are near the start of trace
		if(peak.crossTalk >= 0 && !(ladderPeaks[i].height > meanHeight *2 && peakEndScan(peak) < sample.nScans/3)) {
			heights[nHeights] = ladderPeaks[i].height;
			nHeights++;
		}
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
		[self setLadderFragmentsWithSizes:ladderSizes nSizes:nSizes];;		/// we still create ladder fragments, which will have no scan but can still assigned manually on a traceView
		[sample setLinearCoefsForReadLength:ladderSizes[nSizes-1].size + 50.0];
		return;
	}
	meanHeight = sumHeight/n;
	
	/// we select "valid" peaks for the sizing. Their height should not sufficient and they should not result from crosstalk
	n = 0;
	for (int i = 0; i < nPeaks; i++) {
		if(ladderPeaks[i].height*2 >= minHeight && ladderPeaks[i].crossTalk >= 0) {
			/// We ignore peaks resulting from crosstalk although the code afterwards still checks for crosstalk for peak selection,
			/// as we previously were still considering crosstalk peaks.I left these checks in the code in case we need them.
			/// A peak resulting from crosstalk could be valid if a ladder fragment has the same size as a fragment in another channel.
			/// But currently, this peak is ignored. I believe it is safer to let the user assign it manually.
			if(i!=n) {
				ladderPeaks[n] = ladderPeaks[i];
			}
			n++;
		} else {
			ladderPeaks[i].area = 0;
		}
	}
	nPeaks = n;
	
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
	
	for (int last = nPeaks-1; last+1 >= minNSizes; last--) {		  		  	/// decrementing last peak index
		for (int lastSize = nSizes-1; lastSize+1 >= minNSizes; lastSize--) {  	/// decrementing last size index
			ladderPeaks[last].size = ladderSizes[lastSize].size;
			for (int first = 0; last - first +1 >= minNSizes; first++) {	  	/// incrementing first peak index
				
				/// we compute the slope and intercept of the line passing through the first and last peak (x = scan number, y = size)
				float slope = (ladderPeaks[last].size - ladderPeaks[first].size) / (ladderPeaks[last].scan - ladderPeaks[first].scan);
				float intercept = (ladderPeaks[last].size + ladderPeaks[first].size)/2 - slope * (ladderPeaks[last].scan + ladderPeaks[first].scan)/2;
				
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
					ladderSizes[i].peak = NULL;
				}
				ladderSizes[lastSize].peak = &ladderPeaks[last];
				
				
				int sizeIndex = lastSize-1;		/// the index of the size the peak will be assigned to
				
				/// we assign peaks to sizes from right to left. This is because the left part of the trace often contains noise
				for(int i = last-1; i >= 0; i--) {
					ladderPeaks[i].offset = INFINITY;
					for(int j = sizeIndex; j >= 0; j--) {
						/// we inspect sizes from right to left to see which is the most suitable for the peak
						/// to predict the location of the peak to a lower size than the last assigned one, we use the  slope and intercept
						float predictedSize = (j < leftAssignedSize)? localSlope*ladderPeaks[i].scan + localIntercept : slope*ladderPeaks[i].scan + intercept;
						float offset = ladderSizes[j].size - predictedSize;
						float offsetRatio = offset / ladderPeaks[i].offset ;
						if(fabs(offsetRatio) < 1) {
							/// if the peak is closer to the current size than the previous size
							if(offsetRatio <= -0.3 && ladderPeaks[i].offset > -10) {
								/// we do further inspection if the current size isn't much closer (not more than 3x closer) and if the previous offset is not too large.
								/// The negative ratio means that the peak is between both sizes (previous offset is negative, current is positive)
								/// We do these checks to make sure the previous size isn't skipped with no peak assigned
								LadderSize previousSize = ladderSizes[j+1];
								/// if the previous size has no peak or has a peak of poor quality peak (crosstalk, etc.), we don't take the current size and keep the previous
								if (previousSize.peak == NULL) {
									break;
								}
								LadderPeak previous = *previousSize.peak;
								if(previous.crossTalk < 0 || previous.height < meanHeight / 3 || (previous.area/previous.height) > (ladderPeaks[i].area/ladderPeaks[i].height)*2) {
									break;
								}
							}
							if(j == leftAssignedSize -1 && leftAssignedSize != lastSize) {
								/// if the peak appears to correspond to a size that is lower than the last assigned,
								/// we replace the current slope with the local slope (same for intercept)
								slope = localSlope;
								intercept = localIntercept;
							}
							ladderPeaks[i].offset = offset;
							sizeIndex = j;
						} else {
							break;  /// when the offset starts to get higher than the previous one, we can exit (since sizes are decreasing)
						}
					}
					/// based on the offset, we assign the peak to the size (assignment is not guaranteed because some other peaks may be better)
					BOOL assigned = assignPeakToSize(&ladderPeaks[i], &ladderSizes[sizeIndex], meanHeight);
					/// if the peak is assigned, we compute the local slope and intercept based on the peaks assigned to this size and to the previous size										}
					if(assigned && 	fabsf(ladderPeaks[i].offset) < 30)  {
						if(sizeIndex < leftAssignedSize) {
							rightAssignedSize = leftAssignedSize;
							leftAssignedSize = sizeIndex;
						}
						LadderPeak leftPeak = ladderPeaks[i];
						LadderPeak rightPeak = *ladderSizes[rightAssignedSize].peak;
						
						localSlope = (rightPeak.size - leftPeak.size) / (rightPeak.scan - leftPeak.scan);
						localIntercept = (rightPeak.size + leftPeak.size)/2 - localSlope * (rightPeak.scan + leftPeak.scan)/2;
					}
				}
				
				/// we store assigned peaks in the designated array
				int nAssigned = 0, nMissed = 0;
				for (int i = first; i < nPeaks; i++) {
					if(ladderPeaks[i].size >= 0 && i <= last) {
						assignedPeaks[nAssigned] = ladderPeaks[i];
						nAssigned++;
					} else if(ladderPeaks[i].height > minHeight && ladderPeaks[i].crossTalk >= 0) {
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
	for (int i = nSizes; i >= minNSizes; i--) {
		if(bestScores[i] >= threshold) {
			bestAssignment = assignments[i];
			break;
		} else {
			if(bestScores[i] * i/nSizes > topScore) {
				topScore = bestScores[i] * i/nSizes;
				bestAssignment = assignments[i];;
			}
		}
	}
	
	const LadderSize *assigned = bestAssignment.bytes;
	
	[self setLadderFragmentsWithSizes:assigned nSizes:nSizes];;
	
	[sample computeFitting];
}


BOOL assignPeakToSize(LadderPeak  *ladderPeak, LadderSize *ladderSize, float meanHeight) {
	/// This tries to assign peak to a size. "Tries" because the size may already have a "resident" peak with better assignment,
	/// in which case we won't replace it by the peak we try to assign
	/// peakIndex is the index of the peak that we try to assign (from the ladderPeaks array)
	/// sizeIndex is the index of the size we want to assign the peak to (from the ladderSizes array)
	/// lastSize is the index of the last assignable size
	/// meanHeight is used to evaluate peak quality
	/// reassign tells whether we should try to assign the peak to the next size if it couldn't displace the resident. It also tells if  we should assign the resident to the previous size if it was displaced
	
	ladderPeak->size = -1;				/// we deassign the peak
										/// if the peak offset is just too large, we cannot assign it
	if(fabs(ladderPeak->offset) > 15) {
		return NO;
	}
	/// we check if a previously inspected peak is assigned to this size
	if(ladderSize->peak != NULL) {
		LadderPeak candidate = *ladderPeak;
		/// in that case, the candidate may replace the resident for this size
		LadderPeak resident = *ladderSize->peak;
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
			ladderSize->peak->size = -1;
		} else {
			return NO;
		}
	}
	ladderSize->peak = ladderPeak;
	ladderPeak->size = ladderSize->size;
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
			if(size.peak != NULL) {
				fragment.scan = size.peak->scan;
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


