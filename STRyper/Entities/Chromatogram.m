//
//  Chromatogram.m
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



#import "Chromatogram.h"
#import "ABIFparser.h"
#import "SampleFolder.h"
#import "SizeStandard.h"
#import "SizeStandardSize.h"
#import "Mmarker.h"
#import "Panel.h"
#import "Genotype.h"
#import "Allele.h"
@import Accelerate;


CodingObjectKey ChromatogramSizesKey = @"sizes",
ChromatogramSizeStandardKey = @"sizeStandard",
ChromatogramSizingQualityKey = @"sizingQuality",
ChromatogramPanelKey = @"panel",
ChromatogramTracesKey = @"traces",
ChromatogramGenotypesKey = @"genotypes",
ChromatogramCoefsKey = @"coefs",
ChromatogramSampleNameKey = @"sampleName",
ChromatogramSampleTypeKey = @"sampleType",
ChromatogramStandardNameKey = @"standardName",
ChromatogramPanelNameKey = @"panelName",
ChromatogramOwnerKey = @"owner",
ChromatogramResultsGroupKey = @"resultsGroup",
ChromatogramInstrumentKey = @"instrument",
ChromatogramProtocolKey = @"protocol",
ChromatogramGelTypeKey = @"gelType",
ChromatogramRunNameKey = @"runName",
ChromatogramRunStopTimeKey = @"runStopTime",
ChromatogramImportDateKey = @"importDate",
ChromatogramSourceFileKey = @"sourceFile",
ChromatogramCommentKey = @"comment",
ChromatogramPlateKey = @"plate",
ChromatogramWellKey = @"well",
ChromatogramLaneKey = @"lane",
ChromatogramNScansKey = @"nScans",
ChromatogramOffscaleScansKey = @"offScaleScans",
ChromatogramOffscaleRegionsKey = @"offscaleRegions";

NSPasteboardType _Nonnull const ChromatogramObjectIDPasteboardType = @"org.jpeccoud.stryper.chromatogramPasteboardType";

NSPasteboardType _Nonnull const MarkerOffsetPasteboardType = @"org.jpeccoud.stryper.MarkerOffsetPasteboardType";

const float DefaultReadLength = 550.0;


@interface Chromatogram ()

@property (nonatomic) int minScan;
@property (nonatomic) int maxScan;
@property (nonatomic) NSData *sizes;


/// the url of the source file (computed on demand from -sourceFile). We use it to bind to a NSPathControl value.
@property (readonly, nonatomic) NSURL *fileURL;

@end


@interface Chromatogram (DynamicAccessors)

-(void)managedObjectOriginal_setSampleName:(nullable NSString *)name;
-(void)managedObjectOriginal_setSampleType:(nullable NSString *)type;
-(void)managedObjectOriginal_setComment:(nullable NSString *)comment;
-(void)managedObjectOriginal_setFolder:(SampleFolder *)folder;
-(void)managedObjectOriginal_setSizeStandard:(nullable SizeStandard *)sizeStandard;
-(void)managedObjectOriginal_setPolynomialOrder:(int16_t)polynomialOrder;
-(void)managedObjectOriginal_setSizingSlope:(float)sizingSlope;
-(void)managedObjectOriginal_setIntercept:(float)intercept;
-(void)managedObjectOriginal_setSizingQuality:(nullable NSNumber *)sizingQuality;
-(void)managedObjectOriginal_setPanel:(nullable Panel *)panel;
-(void)managedObjectOriginal_setCoefs:(nullable NSData *)coefs;
-(void)managedObjectOriginal_setReverseCoefs:(nullable NSData *)coefs;
-(void)managedObjectOriginal_setTraces:(nullable NSSet<Trace *>*)traces;
-(void)managedObjectOriginal_setGenotypes:(nullable NSSet<Genotype *> *)genotypes;
-(void)managedObjectOriginal_setOffscaleRegions:(nullable NSData *)offscaleRegions;

@end


@interface Chromatogram (CoreDataGeneratedAccessors)

-(void)removeGenotypesObject:(Genotype *)genotype;

@end


@interface Chromatogram (PrimitiveAccessors)

/// Allows quicker access to the trace ``coefs``, which can be accessed often.
- (NSData*)primitiveCoefs;
															
@end


@implementation Chromatogram {
	NSData *previousCoefs; /// Used to determined if sizing coefficients have changed, to update the ``sizes`` attribute in this case..
}

@dynamic comment, gelType, importDate, instrument, lane, nChannels, nScans, offScaleScans, offscaleRegions, owner, panelName, plate, protocol, resultsGroup, runName, runStopTime, sampleName, sampleType, polynomialOrder, intercept, sizingSlope, sizingQuality, coefs, reverseCoefs, sourceFile, well, folder, panel, sizeStandard, standardName, traces, genotypes;

@synthesize sizes = _sizes, readLength = _readLength, minScan = _minScan, maxScan = _maxScan, startSize = _startSize;



# pragma mark - chromatogram creation




+ (nullable instancetype)chromatogramWithABIFFile:(NSString *)path addToFolder:(SampleFolder *)folder error:(NSError **)error {
	NSManagedObjectContext *context = folder.managedObjectContext;
	if(!context) {
		NSLog(@"The provided folder has no managed object context!");
		return nil;
	}
	
	static NSDictionary *itemsToImport, *channelForDyeName;
	if(!itemsToImport) {
		itemsToImport =
		///the items that we import from an ABIF file. keys = item name combined with item number (as per ABIF specs). Value = corresponding attribute names of Chromatogram, except for some which are attributes of Trace
		@{
			@"CMNT1": ChromatogramCommentKey,
			@"CTNM1": ChromatogramPlateKey,
			@"CTOw1": ChromatogramOwnerKey,
			
			/// raw fluorescence data and dye names, not attributes of Chromatogram, but of Trace
			@"DATA1": @"rawData1",
			@"DATA2": @"rawData2",
			@"DATA3": @"rawData3",
			@"DATA4": @"rawData4",
			@"DATA105": @"rawData5",
			@"DyeN1": @"dye1",
			@"DyeN2": @"dye2",
			@"DyeN3": @"dye3",
			@"DyeN4": @"dye4",
			@"DyeN5": @"dye5",
			/********/
			
			@"GTyp1": ChromatogramGelTypeKey,
			@"StdF1": ChromatogramStandardNameKey,
			@"HCFG3": ChromatogramInstrumentKey,
			@"LANE1": ChromatogramLaneKey,
			@"OfSc1": ChromatogramOffscaleScansKey,
			@"RUND2": @"runStopDate",
			@"RUNT2": ChromatogramRunStopTimeKey,
			@"RunN1": ChromatogramRunNameKey,
			@"RPrN1": ChromatogramProtocolKey,
			@"TUBE1": ChromatogramWellKey,
			@"PANL1": ChromatogramPanelNameKey,
			@"RGNm1": ChromatogramResultsGroupKey,
			@"SCAN1": ChromatogramNScansKey,
			@"SpNm1": ChromatogramSampleNameKey,
			@"STYP1": ChromatogramSampleTypeKey,
		};
	}
	
	if(!channelForDyeName) {
		channelForDyeName =
		/// correspondence between dye names and numbers. We use incomplete dye names, to be more flexible
		/// (sometimes, "6-FAM" is preceded by a space in an ABIF file, for instance)
		/// we actually don't use this dictionary as we trust the item number of the raw fluorescence data
		@{
			@"FAM":@(blueChannelNumber),
			@"R110":@(blueChannelNumber),
			@"PET":@(redChannelNumber),
			@"ROX":@(redChannelNumber),
			@"VIC":@(greenChannelNumber),
			@"JOE":@(greenChannelNumber),
			@"HEX":@(greenChannelNumber),
			@"TET":@(greenChannelNumber),
			@"R6":@(greenChannelNumber),
			@"NED":@(blackChannelNumber),
			@"TAMRA": @(orangeChannelNumber),
			@"LIZ":@(blackChannelNumber)
		};
	}
	
	NSError *contentError;
	NSDictionary *sampleElements = [ABIFparser dictionaryWithABIFile:path itemsToImport:itemsToImport error:&contentError];
	
	if(contentError) {
		if(error != NULL) {
			*error = contentError;
		}
		return nil;
	}
	
	Chromatogram *sample = [self chromatogramWithDictionary:sampleElements insertInContext:context path:path error:&contentError];
	if(sample == nil) {
		if(error != NULL) {
			*error = contentError;
		}
		return sample;
	}
	
	/// If we're here, the chromatogram should be valid. We set the source file.
	[sample setPrimitiveValue:path forKey:ChromatogramSourceFileKey];
	sample.folder = folder;
	
	/// We make the sample determine which channel is offscale at saturated regions
	[sample inferOffscaleChannel];
	
	/// once this is done, we make traces find peaks
	for(Trace *trace in sample.traces) {
		[trace findPeaks];
	}
	
	/// The detection of crosstalk must be done after peak are found in all traces.
	for(Trace *trace in sample.traces) {
		[trace findCrossTalk];
	}

	return sample;
	
}

/// Returns a chromatogram based on objects in a supplied dictionary, or `nil` if the dictionary lacks consistent fluorescence data.
///
/// Returns nil and sets the `error`argument if the fluorescence data is inconsistent (missing channel, trace of different lengths, etc.)
/// - Parameters:
///   - sampleContent: The dictionary containing the data to create the chromatogram.
///   - context: The context in which to materialize the chromatogram.
///   - path: The file path of the ABIF file. This is only used to add information to the potential error.
///   - error: On output, any error that prevented creating the chromatogram.
+ (nullable instancetype) chromatogramWithDictionary:(NSDictionary<NSString *, id> *)sampleContent insertInContext:(NSManagedObjectContext *)context path:(NSString *)path error:(NSError **)error  {
	Chromatogram *sample = nil;
	/// we check if the dictionary contains valid data for the traces (the rest is optional)
	/// we will not create a Chromatogram entity otherwise
	/// we will compare the number of data point (scans) per trace. It must be the same
	NSUInteger nScans = [sampleContent[ChromatogramNScansKey] intValue];
	
	/// We create an array that will contain the data necessary to make the traces (5 traces at most)
	NSMutableArray *traceData = [NSMutableArray arrayWithCapacity:5];
	for (ChannelNumber channel = 1; channel <=5; channel++) {
		NSData *fluo = sampleContent[[NSString stringWithFormat:@"rawData%d", channel]];
		NSString *dyeName = sampleContent[[NSString stringWithFormat:@"dye%d", channel]];
		
		if(![fluo isKindOfClass: NSData.class]) {		/// this means that there is no valid data for the corresponding channel
			if(channel < 5 || [dyeName isKindOfClass:NSString.class]) {
				NSString *reason = [NSString stringWithFormat:@"No valid data for fluorescence channel %d.", channel];
				if(error != NULL) {
					*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File %@ has fluorescence data missing.", path]
														suggestion:@""
														  filePath:path
															reason:reason];
				}
				return sample;	/// Channels from 1 to 4 are required.
			} else {
				break;		/// if there is no data for channel 5 and no dye name, we assume that the chromatogram has 4 channels, so we can break
			}
		}
				
		if(![dyeName isKindOfClass:NSString.class]) {
			NSString *reason = [NSString stringWithFormat:@"No dye name found for fluorescence channel %d.", channel];
			if(error != NULL) {
				*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File %@ has fluorescence data missing.", path]
													suggestion:@""
													  filePath:path
														reason:reason];
			}
			return sample;
			
		}
		
		if(fluo.length / sizeof(int16_t) != nScans) {
			NSString *reason = [NSString stringWithFormat:@"Length of fluorescence data for channel %d (%ld bytes) is inconsistent with the number of reported scans (%ld scans)", channel, fluo.length, nScans];
			if(error != NULL) {
				*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File %@ has inconsistent fluorescence data.", path]
													suggestion:@""
													  filePath:path
														reason:reason];
			}
			return sample;
		}
		
		/// We remove spaces that may be present the begining or end of dye names
		dyeName =  [dyeName stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet];
		[traceData addObject: @[fluo, @(channel-1), dyeName]];
		
	}
	
	/// We can  now create the chromatogram object
	sample = [[Chromatogram alloc] initWithEntity:Chromatogram.entity insertIntoManagedObjectContext:context];
	NSDictionary *attributeDescriptions = self.entity.attributesByName;
	[sampleContent enumerateKeysAndObjectsUsingBlock:^(NSString *key, id  _Nonnull obj, BOOL * _Nonnull stop) {
		NSAttributeDescription *desc = attributeDescriptions[key];
		if(desc) {		/// if there is a description for the key, it means it corresponds to a chromatogram attribute.
						/// We check if the data is of the right class
			if([obj isKindOfClass: NSClassFromString(desc.attributeValueClassName)]) {
				[sample setPrimitiveValue:obj forKey:key];
			}
		}
	}];

	
	/// We compute run stop time from two elements: run stop date (day) and run stop time (hour), which were coded separately in the file
	NSMutableArray *dateElements = [NSMutableArray arrayWithCapacity:2];
	for(NSString *time in @[@"runStopDate", ChromatogramRunStopTimeKey]) {
		id value = sampleContent[time];
		if([value isKindOfClass: NSString.class]) {
			[dateElements addObject:value];
		}
	}
	
	if(dateElements.count == 2) {
		NSDateFormatter *formatter = NSDateFormatter.new;
		formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
		NSDate *runStopTime = [formatter dateFromString:[NSString stringWithFormat:@"%@ %@", dateElements.firstObject, dateElements.lastObject]];
		[sample setPrimitiveValue:runStopTime forKey:ChromatogramRunStopTimeKey];
	}
	
	if(sample.sampleName.length == 0) {
		sample.sampleName = sample.well;
	}
	
	/// we create Trace objects
	for(NSArray *traceValues in traceData) {
		ChannelNumber channel = [traceValues[1] shortValue];
		Trace *trace = [[Trace alloc] initWithRawData:traceValues.firstObject addToChromatogram:sample channel:channel];
		trace.dyeName = traceValues.lastObject;
	}
	
	NSUInteger ladderTraceNumber = sample.traces.count > 4? 4 : 3;
	Trace *ladderTrace = [sample traceForChannel:ladderTraceNumber];
	ladderTrace.isLadder = YES;

	return sample;
	
}


- (void)inferOffscaleChannel {
	NSData *offscaleScanData = self.offScaleScans;
	if(offscaleScanData.length == 0) {
		return;
	}
	const int32_t *offscaleScan = offscaleScanData.bytes;
	long nOffScale = offscaleScanData.length/sizeof(int);
	int nScans = self.nScans;
	
	OffscaleRegion *regions = malloc(nOffScale * sizeof(*regions));
	
	int count = 0;		/// the number of separate offscale regions
	int previousScan = -2; int currentScan;
	for (int i = 0; i < nOffScale; i++) {
		currentScan = offscaleScan[i];
		if(currentScan > previousScan + 1 && currentScan < nScans) {
			/// if an offscale scan is not adjacent to another offscale scan, this is a new offscale region
			regions[count].startScan = currentScan;           /// so we record its first scan
			int16_t maxFluo = 0;
			for (Trace *trace in self.traces) {
				/// to determine the channel that is off scale, we just see which has higher fluo in the first scan -1
				/// (not at the tip, as sometimes saturation can truncate a peak)
				int refScan = currentScan -1 >= 0 ? currentScan-1 : 0;
				NSData *rawData = trace.rawData;
				const int16_t *rawFluo = rawData.bytes;
				long nScans = rawData.length/sizeof(int16_t);
				if (refScan < nScans && rawFluo[refScan] > maxFluo) {
					maxFluo = rawFluo[refScan];
					regions[count].channel = trace.channel;
				}
			}
			count++;
		}
		if(count > 0) {
			regions[count-1].regionWidth = currentScan - regions[count-1].startScan + 1;
			previousScan = currentScan;
		}
	}
	
	[self managedObjectOriginal_setOffscaleRegions: [NSData dataWithBytes:regions length:count*sizeof(OffscaleRegion)]];
	free(regions);
	
}


# pragma mark - sizing

- (void)setSizeStandard:(SizeStandard *)sizeStandard {
	[self managedObjectOriginal_setSizeStandard:sizeStandard];
	if(sizeStandard) {
		if(self.polynomialOrder == NoFittingMethod) {
			[self managedObjectOriginal_setPolynomialOrder: [NSUserDefaults.standardUserDefaults integerForKey:DefaultSizingOrder]];
		}
		[self.ladderTrace findLadderFragmentsAndComputeSizing];
	}
}


- (void)computeFitting {
	
	Trace *trace = self.ladderTrace;
	if(!trace) {
		return;
	}
	
	/// To size the sample, we fit a polynomial where the ladder fragments are the points. X = the scan of a fragment and Y = the size in base pair.
	/// The number of points is, of course, the number of ladder fragments
	NSUInteger nFragments = trace.fragments.count;
	
	float scans[nFragments];		/// arrays used to compute the polynomial
	float sizes[nFragments];

	float readLength = (float)DefaultReadLength;	/// the read length we will set in case sizing fails
	int lastPeakScan = 0;
	int nPoints = 0;
	for(LadderFragment *fragment in trace.fragments) {
		float fragmentSize = fragment.size;
		int scan = fragment.scan;
		if(scan > lastPeakScan) {
			lastPeakScan = scan;
		}
		if(fragmentSize + 50.0 > readLength) {
			readLength = fragmentSize + 50.0;
		}
		if(scan > 0) {
			sizes[nPoints] = fragmentSize;
			scans[nPoints] = scan;
			nPoints++;
		}
	}
	
	int k = self.polynomialOrder +1;
		
	if (nPoints < 4 || nPoints < nFragments/2 || k < 1 || k > 3) {
		[self setLinearCoefsForReadLength:readLength];
		return;
	}
	
	/// We compute a linear relation between sizes and scans, which we use as a reference.
	float sizingSlope, intercept;
	regression(scans, sizes, nPoints, &sizingSlope, &intercept);
	
	[self managedObjectOriginal_setSizingSlope:sizingSlope];
	[self managedObjectOriginal_setIntercept:intercept];
	
	float coefs[k+1];			/// This will store the results of the fitting.
	float reversedCoefs[k+1];
	int info = 0;				/// This will tell whether coefficients are computed
	polynomialCoefs(scans, sizes, k, nPoints, coefs, &info);
	
	if(info == 0) {
		self.coefs = [NSData dataWithBytes:coefs length:(k+1)*sizeof(float)];
		polynomialCoefs(sizes, scans, k, nPoints, reversedCoefs, &info);
	}
	
	if(info != 0) {		/// This indicates a failure in finding coefficients.
		NSLog(@"Failed to compute coefficients for sample %@ using polynomial of order %d.", self.sampleName, k);
		[self setLinearCoefsForReadLength:readLength];
		return;
	}
	
	if(k > 1) {
		/// We check if the coefficients yield a curve that never descends before the last ladder peak.
		/// This may occur if peaks have very inappropriate sizes during manual assignment.
		float maxScanSize = yGivenPolynomial(0, coefs, k+1);
		for (int scan = 1; scan < lastPeakScan + 20; scan += 10) { /// We check every 10 scans
			float size = yGivenPolynomial(scan, coefs, k+1);
			if(size < maxScanSize) {
				/// We must the fitting in as certain peaks may not be drawable otherwise, preventing manual assignment to sizes.
				/// The fitting would not be usable anyway.
				[self setLinearCoefsForReadLength:readLength];
				NSLog(@"Fitting too poor.");
				return;
			} else if(size > maxScanSize){
				maxScanSize = size;
			}
		}
	}
	
	[self managedObjectOriginal_setReverseCoefs:[NSData dataWithBytes:reversedCoefs length:(k+1)*sizeof(float)]];
	
	/// Our sizing quality criterion is based on the mean of differences of offsets between adjacent fragments relative to their distance in scans
	/// For that, we sort sizes and scans
	vDSP_vsort(sizes, nPoints, 1);
	vDSP_vsort(scans, nPoints, 1);
	float offsets[nPoints];
	float maxDiffOffset = 0.0;
	for (int i = 0; i < nPoints; i++) {
		offsets[i] = sizes[i] - yGivenPolynomial(scans[i], coefs, k+1);
		if(i > 0) {
			/// we raise to a power here so that larger inconsistencies (greater than 1 bp) have an even more negative effect on the sizing quality.
			float diffOffset = pow(fabs(offsets[i-1] - offsets[i]),2) / fabs(scans[i-1] - scans[i]);
			/// If a peak is assigned to the wrong size, this greatly reduces sizing quality
			
			if(diffOffset > maxDiffOffset) {
				maxDiffOffset = diffOffset;
			}
		}
	}
	
	float score = 1 - maxDiffOffset/0.3 - 0.1*(nFragments-nPoints);
		
	if(score < 0) {
		score = 0;
	}
	
	/// We assign offsets to ladder fragments
	for(LadderFragment *fragment in trace.fragments) {
		float scan = (float)fragment.scan;
		if(scan > 0) {
			for(int i = 0; i < nPoints; i++) {
				if(scan == scans[i]) {
					fragment.offset = offsets[i];
					break;
				}
			}
		} else {
			fragment.offset = 0;
		}
	}
	
	[self setSizingQuality: @(score)];
	
}


-(void)setLinearCoefsForReadLength:(float)readLength {
																	
	float coefs[2] = {0.0, readLength / self.nScans};
	self.coefs = [NSData dataWithBytes: coefs length:2*sizeof(float)];
	
	float reverseCoefs[2] = {-coefs[0]/coefs[1], 1/coefs[1]};
	[self managedObjectOriginal_setReverseCoefs:[NSData dataWithBytes: reverseCoefs length:2*sizeof(float)]];
	[self setSizingQuality:nil];

}

/// Computes the regression between two series of values using ordinary least squares
/// - Parameters:
///   - x: Vector of values of the first variable (the "X axis").
///   - y: Vector of values of the second variable (the "Y axis").
///   - nPoints: Number of values to consider for `x` and `y`.
///   - slope: On output, will contain the computed slope of the regression line.
///   - intercept: On output, will contain the intercept of the regression line.
void regression (float *x, float *y, NSInteger nPoints, float *slope, float *intercept) {
	float sumXX=0, sumXY=0, sumX=0, sumY=0;
	
	for (int point = 0; point<nPoints; point++) {
		sumXX += x[point] * x[point];
		sumX += x[point];
		sumY += y[point];
		sumXY += x[point] * y[point];
	}
	*slope= (nPoints*sumXY - sumX*sumY)/(nPoints*sumXX - pow(sumX, 2));
	*intercept = (sumY - *slope * sumX)/nPoints;
}


void regressionIgnoringPoint (float *x, float *y, NSInteger nPoints, int pointToIgnore, float *slope, float *intercept) {
	float sumXX=0, sumXY=0, sumX=0, sumY=0;
	int n = 0;
	for (int point = 0; point<nPoints; point++) {
		if(point != pointToIgnore) {
			sumXX += x[point] * x[point];
			sumX += x[point];
			sumY += y[point];
			sumXY += x[point] * y[point];
			n++;
		}
	}
	*slope= (n*sumXY - sumX*sumY)/(n*sumXX - pow(sumX, 2));
	*intercept = (sumY - *slope * sumX)/n;
}



/// Fits a polynomial regression of the form y = ax^0 + bx^1 + … + cx^k between two series of values
/// - Parameters:
///   - x: Vector of values of the first variable (the "X axis").
///   - y: Vector of values of the second variable (the "Y axis").
///   - k: The order of the polynomial used for the regression. This must not be negative
///   - nPoints: Number of values to consider for `x` and `y`.
///   - b: On output, the coefficients of the polynomial (i.e., results). There will be `k` + 1 coefficients.
///   - info: On output, te `info` parameter of the `sposv` function, which tells whether the solution has been computed.
void polynomialCoefs(float *x, float *y, int k, int nPoints, float *b, int *info) {
	
	/// we create matrices A and b that specifies the system of equations, as explained in https://neutrium.net/mathematics/least-squares-fitting-of-a-polynomial/ (here A corresponds to the matrix they call "M")
	int dim =  k+1;					/// the dimension of the A matrix used for fitting
	float A[dim*dim];				/// the A matrix in the equation Ax = b that we will solve. x represents the coefficient to estimate. We use a 1-dimension array rather than a matrix [dim][dim] to avoid a warning in the sposv call bellow
	float exponents[nPoints];		/// array that we use to populate A.
	float x2power[nPoints];			/// array that we use to populate A (scans raised to exponents)
	float xy[nPoints];				/// array that we use to populate b (sizes * scans raised to exponents).
	float sum;						/// will hold temporary results from summations
	
	for (int n = 0; n <= 2*k; n++) {
		float exponent = n;									/// we will raise x value to the power of n
		vDSP_vfill(&exponent, exponents, 1, nPoints);		/// for this, we need to create of vector of n's (one n per scan)
		vvpowf(x2power, exponents, x, &nPoints);			/// so we can use this accelerated function (I couldn't find one in Accelerate that uses a scalar for exponent)
		if(n <= k) {
			vDSP_vmul(x2power, 1, y, 1, xy, 1, nPoints);	/// we populate vector b.
			vDSP_sve(xy, 1, &b[n], nPoints);
		}
		vDSP_sve(x2power, 1, &sum, nPoints);				/// we sum the scan2power vector, as A contains such sums
		for (int i = 0; i <= n; i++) {
			int j = n-i;
			if(i > k || j > k) {
				continue;
			}
			A[i*dim + j] = sum;
		}
	}
	
	/// we solve the system Ax = b using LAPACK's sposv, as the A matrix is always symmetric and positive definite
	char uplo = 'U';		/// specifies the lower triangle of the matrix (this doesn't matter since we have filled the whole matrix)
	int nColB = 1;			/// number of columns of b
	sposv_(&uplo, &dim, &nColB, A, &dim, b, &dim, info);		/// results are put in b
	
}


- (float)readLength {
	if(self.sizes.length > 0) {
		return _readLength;
	}
	return DefaultReadLength;
}


-(void)setReadLength:(float)length {
	_readLength = length > MAX_TRACE_LENGTH ? MAX_TRACE_LENGTH : length;
}


-(void)setStartSize:(float)startSize {
	_startSize = startSize > 0.0 ? 0.0 : startSize;
}


- (float)startSize {
	if(self.sizes.length > 0) {
		return _startSize;;
	}
	return 0;
}


- (NSData *)sizes {
	NSData *coefs = self.primitiveCoefs;
	if(_sizes.length == 0 || previousCoefs != coefs) {
		if(!coefs) {
			[self computeFitting];		/// this method modifies core data attribute, hence may generate undo actions that may not be desirable. 
										/// This is why we compute sizing coefficients on sample import.
		}
		[self computeSizes];
	}
	return _sizes;
}


/// Computes and sets the `size` attribute.
- (void)computeSizes {
	
	NSData *coefData = self.coefs;
	previousCoefs = coefData;
	if(self.nScans == 0 || coefData.length == 0) {
		return;
	}
	int nScans = self.nScans;
	float *scans = malloc(nScans * sizeof(float));		/// the scan indices: 0...nScans-1. We use float for compatibility with vDSP functions
	float *computedSizes = calloc(nScans, sizeof(float));
	float *exponents = malloc(nScans * sizeof(float));
	float *scan2power = malloc(nScans * sizeof(float));
	
	float start = 0;
	float B = 1;
	vDSP_vramp(&start, &B, scans, 1, nScans);
	const float *a = coefData.bytes;
	NSInteger order = coefData.length / sizeof(float);
	for (int n = 0; n < order; n++) {
		float exponent = n;						/// we will raise scans to the power of n
		vDSP_vfill(&exponent, exponents, 1, nScans);
		
		/// so we can use this accelerated function (I couldn't find one in Accelerate that uses a scalar for exponent)
		vvpowf(scan2power, exponents, scans, &nScans);
		vDSP_vsmul(scan2power, 1, &a[n], scan2power, 1, nScans);
		vDSP_vadd(computedSizes, 1, scan2power, 1, computedSizes, 1, nScans);
	}
	
	free(scans);
	free(exponents);
	free(scan2power);
	
	/// we compute minScan, maxScan and readLength based on the sizing
	vDSP_Length maxScan = nScans-1, minScan = 0;
	float max = computedSizes[maxScan], min = computedSizes[0];
	
	if(computedSizes[maxScan] < computedSizes[maxScan-1]) {
		vDSP_maxvi(computedSizes, 1, &max, &maxScan, nScans);
	}
	if(computedSizes[0] > computedSizes[1]) {
		vDSP_minvi(computedSizes, 1, &min, &minScan, maxScan);
	}
	self.startSize = min;
	self.readLength = max;
	self.minScan = (int)minScan;
	self.maxScan = (int)maxScan;
	
	self.sizes = [NSData dataWithBytes:computedSizes length:nScans * sizeof(float)];
	
	free(computedSizes);
	
}


- (int)maxScan {
	if(self.sizes.length > 0) {
		return _maxScan;;
	}
	return self.nScans;
}


- (float)sizeForScan:(int)scan {
	NSData *coefData = self.coefs;
	if(!coefData) {
		[self computeFitting];
		coefData = self.coefs;
		if(!coefData) {
			return -1;
		}
	}
	return yGivenPolynomial(scan, coefData.bytes, (int)coefData.length/sizeof(float));
}


- (int)scanForSize:(float)size {
	NSData *reverseCoefs = self.reverseCoefs;
	if(!reverseCoefs) {
		[self computeFitting];
		reverseCoefs = self.reverseCoefs;
		if(!reverseCoefs || !self.coefs) {
			return -1;
		}
	}
	int scan = yGivenPolynomial(size, reverseCoefs.bytes, (int)reverseCoefs.length/sizeof(float));
	
	/// the scan returned may not be the closest to the size, as the reverse coefs do not do the exact reverse of what the coefs do (which is expected)
	/// but as this scan should be close to the scan we want, we find it by iteration
	NSData *sizeData = self.sizes;
	const float *sizes = sizeData.bytes;
	long nScans = sizeData.length/sizeof(float);
	if (scan > nScans-1 || scan < 0) {
		return scan;
	}
	float dist = sizes[scan] - size;
	float minDist = fabs(dist);
	int increment = dist < 0? 1 : -1;
	while (scan > 0 && scan < nScans-1) {
		scan += increment;
		dist = fabs(sizes[scan] - size);
		if(dist > minDist) {
			scan -= increment;
			break;
		} else {
			minDist = dist;
		}
	}
	
	return scan;
}

/// Returns the value of `y` given the value of `x` assuming a relationship y = ax^0 + bx^1 + … + cx^k
///
/// - Parameters:
///   - x: The value for which we want to compute the y value.
///   - coefs: The coefficient of the polynomial (a, b, c... see description).
///   - k: The order of the polynomial (the number of values in `coefs`, minus one).
float yGivenPolynomial(float x, const float *coefs, int k) {
	float y = 0;
	for (int n = 0; n < k; n++) {
		y += coefs[n] * pow(x, n);
	}
	return y;
}


- (nullable Trace *)ladderTrace {		/// returns the trace that is the ladder
	for(Trace *trace in self.traces) {
		if(trace.isLadder) {
			return trace;
		}
	}
	return nil;
}



+ (NSSet<NSString *> *)keyPathsForValuesAffectingBoundSizeStandard {
	return [NSSet setWithObject:ChromatogramSizeStandardKey];
}


- (Genotype *)genotypeForMarker:(Mmarker *)marker {
	for(Genotype *genotype in self.genotypes) {
		if(genotype.marker == marker) {
			return genotype;
		}
	}
	return nil;
}


- (nullable NSSet<Genotype *> *)genotypesForChannel:(NSInteger)channel {
	return [self.genotypes filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Genotype *genotype, NSDictionary<NSString *,id> * _Nullable bindings) {
		return genotype.marker.channel == channel;
	}]];
}

#pragma mark - accessors

- (NSString *)dye1 {
	return [self traceForChannel:0].dyeName;
}


- (NSString *)dye2 {
	return [self traceForChannel:1].dyeName;
}


- (NSString *)dye3 {
	return [self traceForChannel:2].dyeName;
}


- (NSString *)dye4 {
	return [self traceForChannel:3].dyeName;
}


- (NSString *)dye5 {
	return [self traceForChannel:4].dyeName;
}


- (NSURL *)fileURL {
	if(self.sourceFile) {
		return [NSURL fileURLWithPath:self.sourceFile];
	}
	return nil;
}




- (void)setPolynomialOrder:(PolynomialOrder)polynomialOrder {
	if(polynomialOrder < -1 || polynomialOrder > 3 || polynomialOrder == self.polynomialOrder) {
		return;
	}
	[self managedObjectOriginal_setPolynomialOrder:polynomialOrder];
	
	if(!self.deleted) {
		[self computeFitting];
	}
}



-(void)applyPanelWithAlleleName:(NSString *)alleleName {
	/// we remove genotypes the sample may have from a previous panel (genotypes delete themselves when they lose their sample)
	[self managedObjectOriginal_setGenotypes:nil];
	if (self.panel) {
		for (Mmarker *marker in self.panel.markers) {
			Genotype *newGenotype = [[Genotype alloc] initWithMarker:marker sample:self];
			if(newGenotype) {
				for(Allele *allele in newGenotype.alleles) {
					[allele managedObjectOriginal_setName:alleleName];
				}
			}
		}
	}
}


- (void)setCoefs:(NSData *)coefs {
	[self managedObjectOriginal_setCoefs:coefs];
	/// when sizing has changed, we recompute allele sizes
	for(Genotype *genotype in self.genotypes) {
		for(Allele *allele in genotype.alleles) {
			[allele computeSize];
		}
		genotype.status = genotype.status == genotypeStatusNoSizing? genotypeStatusNotCalled : genotypeStatusSizingChanged;
	}
}


-(void)setSizingQuality:(NSNumber * _Nullable)sizingQuality {
	[self managedObjectOriginal_setSizingQuality:sizingQuality];
	if(sizingQuality.floatValue <= 0) {
		for(Genotype *genotype in self.genotypes) {
			genotype.status = genotypeStatusNoSizing;
			for(Allele *allele in genotype.alleles) {
				allele.scan = 0;
			}
		}
	}
}


- (Folder *)topAncestor {
	Folder *parent = self.folder;
	while(parent.parent) {
		parent = parent.parent;
	}
	return parent;
}


# pragma mark - other methods related to trace, folder and panel management


- (nullable Trace *)traceForChannel:(ChannelNumber)channel {
	for(Trace *trace in self.traces) {
		if(trace.channel == channel) {
			return trace;
		}
	}
	return nil;
}


/*
int scanForSize(float size, const float *reverseCoefs, int k) {
	
	
	float minus = -size;
	vDSP_vsadd(sizes, 1, &minus, buffer, 1, nScans);
	float min; vDSP_Length scan = 0;
	vDSP_minmgvi(buffer, 1, &min, &scan, nScans);
	return (int)scan;

}  */


- (BOOL)validateSampleName:(id *) value error:(NSError **)error {
	/// the sample must have a name
	NSString *name = *value;
	if(name.length < 0) {
		if (error != NULL) {
			*error = [NSError managedObjectValidationErrorWithDescription:@"The sample must have a name."
															   suggestion:@""
																   object:self
																   reason:@"The sample must have a name."];

		}
		return NO;
	}
	return YES;
}


- (BOOL)validateTraces:(id *)valueRef error:(NSError **)error {
	NSSet *traces = *valueRef;
	NSUInteger refLen = 0;
	for(Trace *trace in traces) {
		NSUInteger len = trace.rawData.length;
		if(len != refLen && refLen != 0) {
			if(error != NULL) {
				*error = [NSError managedObjectValidationErrorWithDescription:[NSString stringWithFormat:@"The chromatogram contains invalid fluorescent data."]
																   suggestion:@""
																	   object:self
																	   reason:[NSString stringWithFormat:@"The chromatogram's traces have different lengths: %ld and %ld bytes.", refLen, len]];
			}
			return NO;
		}
	}
	return YES;
}


# pragma mark - archiving and copying

+(BOOL)supportsSecureCoding {
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {		
	/// we encode all relationships, except the parent folder. This relationship is already covered (in the opposite direction) by the sample folder when it is encoded
	NSProgress *currentProgress = NSProgress.currentProgress;
	if(currentProgress.isCancelled) {
		return;
	}
	
	/// For backwards compatibility, we use the initial name for the `Trace` class to encode traces.
	NSKeyedArchiver *encoder = (NSKeyedArchiver *)coder;
	if([encoder respondsToSelector:@selector(setClassName:forClass:)]) {
		Class traceClass = FluoTrace.class;
		if([encoder classNameForClass:traceClass] != previousTraceClassName) {
			[encoder setClassName:previousTraceClassName forClass:traceClass];
		}
	}
	
	[super encodeWithCoder:coder];
	[coder encodeObject:self.panel forKey:ChromatogramPanelKey];
	[coder encodeObject:self.sizeStandard forKey:ChromatogramSizeStandardKey];
	[coder encodeObject:self.traces forKey:ChromatogramTracesKey];
	[coder encodeObject:self.genotypes forKey:ChromatogramGenotypesKey];
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	if(NSProgress.currentProgress.isCancelled) {
		return nil;  // TO CHECK
	}
	self = [super initWithCoder:coder];
	if(self) {
		
		NSSet <NSString *>*identifiers = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, NSString.class, nil]  forKey:NSStringFromSelector(@selector(versionIdentifiers))];

		/// To read archives, we need to set the class for the initial name for the `Trace` class.
		NSKeyedUnarchiver *decoder = (NSKeyedUnarchiver *)coder;
		if([decoder respondsToSelector:@selector(setClass:forClassName:)]) {
			Class traceClass = FluoTrace.class;
			if([decoder classForClassName:previousTraceClassName] != traceClass) {
				[decoder setClass:traceClass forClassName:previousTraceClassName];
			}
		}
		
		[self managedObjectOriginal_setPanel: [coder decodeObjectOfClass:Panel.class forKey:ChromatogramPanelKey]];	/// it is important to decode the panel first, as it may be replaced by one already in the store
		[self managedObjectOriginal_setSizeStandard: [coder decodeObjectOfClass:SizeStandard.class forKey:ChromatogramSizeStandardKey]];
		[self managedObjectOriginal_setTraces: [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Trace.class, nil] forKey:ChromatogramTracesKey]];
		[self managedObjectOriginal_setGenotypes: [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Genotype.class, nil]  forKey:ChromatogramGenotypesKey]];
		
		if(![identifiers containsObject:@"1.2"]) {
			/// Crosstalk detection was improved in this version.
			for (Trace *trace in self.traces) {
				[trace findCrossTalk];
			}
		}
	}
	return self;
}



- (id)copy {
	Chromatogram *copy = super.copy;
	Panel *panel = self.panel;
	if(panel) {
		[copy managedObjectOriginal_setPanel:panel];
	}
	
	/// as genotypes are copied, their alleles must be assigned to traces
	for(Genotype *genotype in copy.genotypes) {
		Trace *trace = [copy traceForChannel:genotype.marker.channel];
		if(trace) {
			for(Allele *allele in genotype.alleles) {
				[allele managedObjectOriginal_setTrace: trace];
			}
		}
	}
	
	SizeStandard *standard = self.sizeStandard;
	if(standard) {
		[copy managedObjectOriginal_setSizeStandard:standard];
	}
	
	return copy;
}

/// We don't implement the NSPasteboardReading protocol, because we wouldn't know which managed object context to use to init an instance from the paste board

- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[ChromatogramObjectIDPasteboardType, MarkerOffsetPasteboardType];
}


- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard {
	if([type isEqualToString:ChromatogramObjectIDPasteboardType]) {
		/// we don't write a chromatogram to the pasteboard, we only write it when required (upon paste)
		return NSPasteboardWritingPromised;
	}
	return 0;
}


- (id)pasteboardPropertyListForType:(NSPasteboardType)type {
		
	if([type isEqualToString:ChromatogramObjectIDPasteboardType]) {
		if(self.isDeleted || !self.traces) {
			/// in case the user tries to paste a sample that is deleted (which currently can only happen after undoing a sample import)
			return nil;
		}
		
		/// since we write our object id, we must ensure that it is not temporary.
		if(self.objectID.isTemporaryID) {
			if(![self.managedObjectContext obtainPermanentIDsForObjects:@[self] error:nil]) {
				NSLog(@"Error obtaining permanent ID for sample '%@': copy not made.", self.description);
				return nil;
			}
		}
		
		return self.objectID.URIRepresentation.absoluteString;
	}
	
	if([type isEqualToString:MarkerOffsetPasteboardType]) {
		return [self dictionaryForOffsetsAtMarkers:nil];
	}
	
	return nil;
}


- (nullable NSDictionary *)dictionaryForOffsetsAtMarkers:(nullable NSArray<Mmarker *> *)markers {
	NSSet *genotypes = self.genotypes;
	if(genotypes.count > 0) {
		NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithCapacity:genotypes.count];
		for(Genotype *genotype in genotypes) {
			Mmarker *marker = genotype.marker;
			if(markers == nil || [markers indexOfObjectIdenticalTo:marker] != NSNotFound) {
				MarkerOffset offset = genotype.offset;
				if(offset.intercept != 0.0 || offset.slope != 1.0) {
					NSString *URI = marker.objectID.URIRepresentation.absoluteString;
					if(URI) {
						dic[URI] = genotype.offsetData;
					}
				}
			}
		}
		return dic;
	}
	return nil;
}


+(nullable NSDictionary *)markerOffsetDictionaryFromGeneralPasteBoard {
	NSPasteboard *pboard = NSPasteboard.generalPasteboard;
	if([pboard.types containsObject:MarkerOffsetPasteboardType]) {
		NSDictionary *dic = [pboard propertyListForType:MarkerOffsetPasteboardType];
		if([dic isKindOfClass:NSDictionary.class]) {
			return dic;
		}
	}
	return nil;
}


-(void)refreshSizeData {
	if(_sizes) {
		self.sizes = nil;
	}
}


- (void)didTurnIntoFault {
	[super didTurnIntoFault];
	if(_sizes) {
		self.sizes = nil;
	}
}


@end
