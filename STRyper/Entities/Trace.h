//
//  Trace.h
//  STRyper
//
//  Created by Jean Peccoud on 18/08/2014.
//  Copyright (c) 2014 Jean Peccoud. All rights reserved.

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

@class Chromatogram, TraceView, LadderFragment, ViewLabel, PeakLabel, FragmentLabel, Allele;

NS_ASSUME_NONNULL_BEGIN

/// An entity that stores the fluorescence data of a ``Chromatogram`` object for a channel (wave length).
///
/// A trace contains fluorescence data obtained from a given ``channel``, as well as information related to peaks found in the data.
///
/// This class implements a method that finds peaks that corresponds to ``SizeStandard/sizes`` of a size standard.
@interface Trace : CodingObject

/// An integer from 0 to 4 that represents the channel (wavelength) of the fluorescence data.
///
/// This number denotes the conventional order of the channels of a capillary sequencer: blue, green, black/yellow, red, orange.
///
/// The channel number corresponds to the ABIF convention minus one, as the [the ABIF file format specifications](https://www.wikidata.org/wiki/Q43992376) use numbers from 1 to 5 to denote channels.
typedef enum ChannelNumber : int16_t {
	
	/// The first channel (number 0), represented by a blue color.
	blueChannelNumber = 0,
	
	/// The second channel (number 1), represented by a green color.
	greenChannelNumber = 1,
	
	/// The third channel (number 2), represented by a black or yellow color.
	blackChannelNumber = 2,
	
	/// The forth channel (number 3), represented by a red color.
	redChannelNumber = 3,
	
	/// The fifth channel (number 4), represented by an orange color.
	orangeChannelNumber = 4,
} ChannelNumber;


/// The chromatogram to which the trace belongs.
///
/// The reverse relationship is ``Chromatogram/traces`` of  ``Chromatogram``.
@property (nonatomic, readonly) Chromatogram *chromatogram;
															   
/// Inits a trace with raw fluorescence data and adds it to a sample for a given channel.
///
/// This method does not check if `rawData` is consistent with other ``Chromatogram/traces`` of the sample (for instance, if their ``rawData`` is of the same length)
/// or if some already occupy the `channel`, which would be an error.
/// - Parameters:
///   - rawData:The data that will be set as the trace ``rawData``.
///   - sample: The sample to which the trace will be added
///   - channel: The channel of the trace.
- (instancetype)initWithRawData:(NSData *)rawData addToChromatogram:(Chromatogram *)sample channel:(ChannelNumber)channel;

#pragma mark - fluorescence data


/// The raw fluorescence level for all scans (array of 16-bit integers).
///
/// The number of data point in this array should correspond to the ``Chromatogram/nScans`` value of the ``chromatogram``.
@property (nonatomic, readonly) NSData *rawData;

/// Returns the fluorescence data (array of 16-bit integers) with baseline "noise" removed.
///
/// This can be used to draw fluorescence curves in which peaks stand out more.
/// - Parameter maintainPeakHeights: Whether the fluorescence level of the tips of ``peaks``  should be the same as those in ``rawData``.
/// If `NO` the height of peaks is reduced by subtracting the baseline level.
- (NSData *)adjustedDataMaintainingPeakHeights:(BOOL) maintainPeakHeights;


/// The name of the dye that emitted the fluorescence (e.g., "6-FAM").
@property (nonatomic) NSString *dyeName;

/// The channel of the trace.
@property (nonatomic, readonly) ChannelNumber channel;


/// The highest fluorescent value across all scans for a trace.
@property (nonatomic, readonly) int16_t maxFluo;

#pragma mark - peaks in the fluorescence data

/// A structure that defines a peak in the fluorescence data.
typedef struct Peak {
	/// The scan number at which the peak starts.
	int32_t startScan;
	
	/// The number of scans between the `startScan` and the tip of the peak.
	int32_t scansToTip;
	
	/// The number of scans from the peak tip to the end of the peak.
	int32_t scansFromTip;
	/// this structure complicates the code as we frequently compute the scan of the peak tip or peak end, but it ensures that the peak structure is consistent (peak tip between start and ends, for instance).
	
	/// Indicates saturation or crosstalk in fluorescence at the peak location.
	///
	/// A positive value represents the width of the offscale region (see ``Chromatogram/offscaleRegions``) at the peak location.
	/// A negative value between -1 and -5 represents the opposite of the ``Trace/channel`` that induced crosstalk, minus 1
	/// (e.g., a value of -3 represents channel 4), meaning that the peak results from crosstalk.
	int32_t crossTalk;
} Peak;

/// Returns a ``Peak`` struct with its specified members.
Peak MakePeak(int32_t startScan, int32_t scansToTip, int32_t scansFromTip, int32_t crossTalk);

/// Convenience function that returns the scan number at the end of a peak.
/// - Parameter peakPTR: Pointer to the peak.
int32_t peakEndScan(const Peak *peakPTR);

/// The array of peaks (``Peak`` structs) that were detected in the fluorescence data, in ascending scan order.
@property (nonatomic, readonly) NSData *peaks;

/// Makes the trace set its ``peaks`` attribute by analyzing its fluorescence data.
- (void)findPeaks;

/// Makes the trace determine whether each if its peak results from crosstalk.
///
/// The method sets the `crossTalk` member of each peak in ``peaks``.
///
/// **IMPORTANT:** the method relies on ``peaks`` found in the other ``Chromatogram/traces`` of the ``chromatogram``.
- (void)findCrossTalk;

/// The minimum fluorescence level that a ``Peak`` must have to be detected.
///
/// The default value is 100.
@property (nonatomic) int16_t peakThreshold;

/// Returns a peak that had not beed detected in the fluorescence data at a scan number.
///
/// If a peak comprising the `scan` already exists, of if no peak can be found at that `scan`, the methods returns a ``Peak`` with all members set to 0.
///
/// This method can be used to "force" the trace to find a peak that may be below the ``peakThreshold``. However, the tip of the peak must be at least twice higher than its surroundings (which must not include other peaks).
/// - Parameters:
///   - scan: The scan at which to look for a peak. The tip of the returned peak may not be at that scan.
///   - useRawData: Whether the method should use the trace ``rawData`` (if `YES`) or the data with baseline fluorescence level subtracted.
- (Peak)missingPeakForScan:(int)scan useRawData:(BOOL)useRawData;


/// Tries to insert a new peak in the ``Trace/peaks`` array and returns whether the peak was inserted.
///
/// The peak is inserted at an index that maintains the ascending order of the ``Trace/peaks`` in the array (with respect to their `startScan`).
/// This method logs an error message and returns `NO` if an existing peak overlaps the peak to insert.
/// The method does not check if the peak to insert indeed covers a region where the fluorescence actually shows a peak.
/// - Parameter newPeak: The peak to insert.
- (BOOL)insertPeak:(Peak)peak;

#pragma mark - fragments associated with the traces

/// Whether the trace represents the molecular ladder of its ``chromatogram``.
///
/// The molecular ladder is the trace whose ``channel`` is the fifth  channel, or the fourth channel if the sample has only four.
@property (nonatomic) BOOL isLadder;

/// The DNA fragments that were identified in the fluorescence data of the trace.
///
/// If the trace returns `YES` to ``isLadder``  these fragment must be ``LadderFragment`` objects. Otherwise, they must be ``Allele`` objects.
/// Methods implemented by this class do not check this condition.
///
/// The reverse relationship is ``LadderFragment/trace`` from ``LadderFragment``.
/// This relationship is encoded in ``CodingObject/encodeWithCoder:``  and decoded in ``CodingObject/initWithCoder:``.
@property (nonatomic) NSSet<LadderFragment *> *fragments;

/// Finds ladder fragments based on the  chromatogram's size standard.
///
/// This method finds peaks that may correspond to the ``SizeStandard/sizes`` of the ``Chromatogram/sizeStandard``,
/// sets the trace's ``fragments`` accordingly and calls ``Chromatogram/computeFitting`` on its ``chromatogram``.
///
/// This method does nothing is the trace returns `NO` to ``isLadder`` or if its ``chromatogram`` has no size standard.
- (void)findLadderFragmentsAndComputeSizing;



#pragma mark - range and display properties

/// A structure that defines a range in base pairs, which can represent a segment of a ``Trace`` object.
typedef struct BaseRange {
	/// The start position of the range.
	float start;
	
	/// The length of the range, which in principle should not be negative.
	float len;
} BaseRange;

/// Returns a BaseRange struct given its members.
BaseRange MakeBaseRange(float start, float len);

/// The visible range of the trace in a view.
///
/// A trace is likely to be displayed in a row of a table. As `NSTableView` objects shuffle and reuse views for rows and cells,
/// a trace may be randomly shown in different views (``TraceView`` objects).
///
/// A ``TraceView`` can use this property to set its ``TraceView/visibleRange``.
@property (nonatomic) BaseRange visibleRange;

/// The maximum fluorescent level that a view can set to display the trace.
///
/// A trace is likely to be displayed in a row of a table. As `NSTableView` objects shuffle and reuse views for rows and cells,
/// a trace may be randomly shown in different views (``TraceView`` objects)..
///
/// A ``TraceView`` can use this property to set  its ``TraceView/topFluoLevel``.
@property (nonatomic) float topFluoLevel;

/// Returns the fluorescence level (RFU) for a scan in the trace.
///
/// This method returns 0 if the scan is out of range (negative of beyond the number of recorded scans).
/// - Parameters:
///   - scan: The scan at which to return the fluorescent level.
///   - useRawData: Whether the fluorescent level should be extracted from the trace ``rawData``.
///   - maintainPeakHeights: if `useRawData` is `YES`, whether the fluorescence data to use should maintain peak heights (see ``adjustedDataMaintainingPeakHeights:``).
-(int16_t) fluoForScan:(int)scan useRawData:(BOOL)useRawData maintainPeakHeights:(BOOL)maintainPeakHeights;

/// This method does the same as ``Chromatogram/sizeForScan:`` of ``Chromatogram``,
/// but accounts for the possible ``Genotype/offset`` of the marker that may cover the scan.
-(float) sizeForScan:(int)scan;

/// Returns a copy of the receiver, as well as of its ``fragments`` if ``isLadder`` returns `NO`.
///
/// If the trace is not a ladder, its ``fragments`` are ``Genotype/alleles`` of
/// a sample's ``Chromatogram/genotypes``, which are copied if the sample is copied. This method does not copy them to avoid duplicates.
-(instancetype) copy;

@end



/// Constants  used to avoid typos in key names.
extern CodingObjectKey TraceIsLadderKey,
TracePeaksKey,
TraceFragmentsKey;


@interface Trace (PrimitiveAccessors)

/// Allows quicker access to the trace ``rawData``, which can be accessed often.
- (NSData*)primitiveRawData;

															
@end




NS_ASSUME_NONNULL_END
