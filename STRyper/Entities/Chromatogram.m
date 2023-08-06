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
#import "LadderFragment.h"
#import "SampleFolder.h"
#import "SizeStandard.h"
#import "SizeStandardSize.h"
#import "Trace.h"
#import "Mmarker.h"
#import "Panel.h"
#import "Genotype.h"
#import "Allele.h"
@import Accelerate;


NSString * _Nonnull const ChromatogramSizesKey = @"sizes";
NSString * _Nonnull const ChromatogramSizeStandardKey = @"sizeStandard";
NSString * _Nonnull const ChromatogramSizingQualityKey = @"sizingQuality";
NSString * _Nonnull const ChromatogramPanelKey = @"panel";
NSString * _Nonnull const ChromatogramTracesKey = @"traces";
NSString * _Nonnull const ChromatogramGenotypesKey = @"genotypes";
NSString * _Nonnull const ChromatogramCoefsKey = @"coefs";
NSString * _Nonnull const ChromatogramSampleNameKey = @"sampleName";
NSString * _Nonnull const ChromatogramSampleTypeKey = @"sampleType";
NSString * _Nonnull const ChromatogramStandardNameKey = @"standardName";
NSString * _Nonnull const ChromatogramPanelNameKey = @"panelName";
NSString * _Nonnull const ChromatogramOwnerKey = @"owner";
NSString * _Nonnull const ChromatogramResultsGroupKey = @"resultsGroup";
NSString * _Nonnull const ChromatogramInstrumentKey = @"instrument";
NSString * _Nonnull const ChromatogramProtocolKey = @"protocol";
NSString * _Nonnull const ChromatogramGelTypeKey = @"gelType";
NSString * _Nonnull const ChromatogramRunNameKey = @"runName";
NSString * _Nonnull const ChromatogramRunStopTimeKey = @"runStopTime";
NSString * _Nonnull const ChromatogramImportDateKey = @"importDate";
NSString * _Nonnull const ChromatogramSourceFileKey = @"sourceFile";
NSString * _Nonnull const ChromatogramCommentKey = @"comment";
NSString * _Nonnull const ChromatogramPlateKey = @"plate";
NSString * _Nonnull const ChromatogramWellKey = @"well";
NSString * _Nonnull const ChromatogramLaneKey = @"lane";
NSString * _Nonnull const ChromatogramNScansKey = @"nScans";
NSString * _Nonnull const ChromatogramOffscaleScansKey = @"offScaleScans";
NSString * _Nonnull const ChromatogramOffscaleRegionsKey = @"offscaleRegions";

NSPasteboardType _Nonnull const ChromatogramPasteboardType = @"org.jpeccoud.stryper.chromatogramPasteboardType";

const float DefaultReadLength	= 550.0;


@interface Chromatogram ()

@property (nonatomic, readwrite) int minScan;
@property (nonatomic, readwrite) int maxScan;

/// the url of the source file (computed on demand from -sourceFile). We use it to bind to a NSPathControl value.
@property (readonly, nonatomic) NSURL *fileURL;

/// use to bind the size standard to UI elements (NSPopupButton) and apply the standard with a custom setter (as we don't override setSizeStandard)
@property (nonatomic) SizeStandard *boundSizeStandard;

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
-(nullable NSSet *)managedObjectOriginal_genotypes;

@end


@interface Chromatogram (CoreDataGeneratedAccessors)

-(void)removeGenotypesObject:(Genotype *)genotype;

@end


@implementation Chromatogram

@dynamic comment, gelType, importDate, instrument, lane, nChannels, nScans, offScaleScans, offscaleRegions, owner, panelName, plate, protocol, resultsGroup, runName, runStopTime, sampleName, sampleType, polynomialOrder, intercept, sizingSlope, sizingQuality, coefs, reverseCoefs, sourceFile, well, folder, panel, sizeStandard, standardName, traces, genotypes, panelVersion;

@synthesize sizes = _sizes, readLength = _readLength, minScan = _minScan, maxScan = _maxScan, startSize = _startSize, boundSizeStandard = _boundSizeStandard;

/// some arrays of dictionaries we use when importing an ABIF file (see +initialize)
NSArray *colors;		/// the colors of the dyes in order
static NSDictionary *itemsToImport, *channelForDyeName;

# pragma mark - chromatogram creation

+ (void)initialize {
	
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
	
	colors = @[@"blue", @"green", @"black", @"red", @"orange"];
	
	channelForDyeName =
	/// correspondence between dye names and numbers. We use incomplete dye names, to be more flexible
	/// (sometimes, "6-FAM" is preceded by a space in an ABIF file, for instance)
	/// we actually don't use this dictionary as we trust the item number of the raw fluorescence data
	@{
		@"FAM":@0,
		@"R110":@0,
		@"PET":@3,
		@"ROX":@3,
		@"VIC":@1,
		@"JOE":@1,
		@"HEX":@1,
		@"TET":@1,
		@"R6":@1,
		@"NED":@2,
		@"TAMRA": @2,
		@"LIZ":@4
	};
	
}



/***  structs and methods used to import an ABIF File  */

/// defines a directory entry: the description and location of an item in an ABIF file, as described in the ABIF format specs
typedef struct __attribute__((__packed__)) DirEntry {
	char itemName[4];					/// the name of the item
	int32_t itemNumber;					/// its number
	int16_t elementType;				/// the element type code (char, byte, short, etc.)
	int16_t elementSize;				/// the size of an element in bytes
	int32_t numElements;				/// the number of elements in the item
	int32_t dataSize;					/// the total size of the data in bytes
	int32_t dataOffset;					/// the offset of the data in the file (in bytes), or the data itself if dataSize ≤ 4
	int32_t dataHandle;					/// reserved to Applied Biosystems (we don't know what this represents)
} DirEntry;


/// The item element types for items we import (other types are not listed here, and are not managed).
typedef enum elementType: int16_t {
	elementTypeWord = 3,				/// an unsigned 16-bit int
	elementTypeShort = 4,				/// signed 16-bit int
	elementTypeLong = 5,				/// a 32-bit int ("Long" is misleading)
	elementTypeDate = 10,
	elementTypeTime = 11,
	elementTypePString = 18,
	elementTypeCString = 19
} elementType;

#define ENTRYSIZE	 28			/// the size of a DirentryEntry in bytes
#define HEADERSIZE	 34			/// the size of an ABIF file header in bytes


+ (nullable instancetype)chromatogramWithABIFFile:(NSString *)path addToFolder:(SampleFolder *)folder error:(NSError **)error {
	NSManagedObjectContext *context = folder.managedObjectContext;
	if(!context) {
		NSLog(@"The provided folder has no managed object context!");
		return nil;
	}
	Chromatogram *sample = nil;
	
	NSString *corruptFileString = [NSString stringWithFormat:@"File '%@' was not imported because it is corrupt.", path];
	
	NSError *readError = nil;
	NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath: path error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return sample;
	}
	
	if( [attributes fileSize] > 1e7) {
		/// We avoid reading a file that is too big
		if (error != NULL){
			NSString *description = [NSString stringWithFormat:@"File '%@' was not imported because it is too large.", path];
			*error = [NSError errorWithDomain:STRyperErrorDomain
										 code:NSFileReadTooLargeError
									 userInfo:@{
				NSLocalizedDescriptionKey: description,
				NSLocalizedRecoverySuggestionErrorKey: @"Check that the file is a chromatogram file.",
				NSFilePathErrorKey: path
			}];
		}
		return sample;
	}
	
	NSData *fileData = [NSData dataWithContentsOfFile:path options:NSDataReadingMapped error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return sample;
	}
	
	if(fileData.length < HEADERSIZE) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"File size of %ld bytes is less than expected header size of %d bytes.", fileData.length, HEADERSIZE];
			*error = [NSError fileReadErrorWithDescription:corruptFileString
												suggestion:@""
												  filePath:path
													reason:reason];
		}
		return sample;
	}
	
	/// We check it is a supported file type "ABIF" (the first bytes of the file)
	const char *fileBytes = fileData.bytes;
	if(strncmp(fileBytes, "ABIF", 4) != 0) {
		if (error != NULL) {
			NSString *code = [[NSString alloc] initWithBytes:fileBytes length:4 encoding:NSASCIIStringEncoding];
			NSString *reason = [NSString stringWithFormat:@"Header '%@' does not correspond to expected header 'ABIF'.", code];
			*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File '%@' was not imported because it was not recognized as a chromatogram file.", path]
												suggestion:@""
												  filePath:path
													reason:reason];
		}
		return sample;
	}
	
	/// We check the ABIF version, which is stored as a short after the first 4 bytes
	int16_t version = EndianS16_BtoN(*(const int16_t *)(fileBytes + 4));
	if(version >= 400 || version < 100) {
		/// 4.00 is arbitrary. Specs of version ≥ 1.0x are not public, there is no guaranty to import the file correctly.
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"File version %.01f is unsupported (min supported: 1.00, max supported: 4.00)", (float)version/100];
			*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File '%@' was not imported because it the ABIF version is not supported by this application.", path]
												suggestion:@""
												  filePath:path
													reason:reason];
		}
		return sample;
	}
	
	/// We read the file's first entry that lists the directory's contents, and is at byte 6
	DirEntry headerEntry = *(const DirEntry *)(fileBytes + 6);
	headerEntry = nativeEndianEntry(headerEntry);
	/// The header entry indicates the number of directory entries and their location. We check if this is consistent.
	if(headerEntry.dataSize < headerEntry.numElements * sizeof(DirEntry) ||
	   (fileData.length < headerEntry.dataOffset + headerEntry.dataSize) || headerEntry.dataOffset < HEADERSIZE) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"File size of %ld bytes is too short given the offset of the directory entry (offset %d).", fileData.length, headerEntry.dataOffset + headerEntry.dataSize];
			*error = [NSError fileReadErrorWithDescription:corruptFileString
												suggestion:@""
												  filePath:path
													reason:reason];
			return sample;
		}
	}
	
	/// The directory is composed of consecutive DirEntry structures starting at the offset indicated by the header,
	/// hence we can just point to the content at the offset
	const DirEntry *entries = (const DirEntry *)(fileBytes + headerEntry.dataOffset);
	/// For each relevant entry, we extract an object and store it in a dictionary in which a key = a chromatogram's attribute name
	/// (except for the fluo data) and value = object for the attribute
	NSMutableDictionary *sampleElements = [NSMutableDictionary dictionaryWithCapacity:headerEntry.numElements];
	
	for (int i = 0; i < headerEntry.numElements; i++) {
		DirEntry entry = entries[i];
		/// We check that the entry corresponds to an element that we import.
		NSString *itemName = [[NSString alloc] initWithBytes:entry.itemName length:4 encoding:NSASCIIStringEncoding];
		itemName = [itemName stringByAppendingFormat:@"%d", EndianS32_BtoN(entry.itemNumber)];
		NSString *attributeName = itemsToImport[itemName];
		if(attributeName != nil) {
			/// If it is an item we import, we retrieve it as an object
			id object = [self objectForDirEntry:entry withABIFData:fileData try:YES];
			if(object == nil) {
				/// The object is nil if the entry is inconsistent
				if(error != NULL) {
					NSString *reason = [NSString stringWithFormat:@"Could not retrieve data for directory entry '%@', corresponding to attribute '%@'.", itemName, attributeName];
					*error = [NSError fileReadErrorWithDescription:corruptFileString
														suggestion:@""
														  filePath:path
															reason:reason];
				}
				return sample;	/// We return upon the first error
			} else {
				sampleElements[attributeName] = object;
			}
		}
	}
	
	NSError *contentError;
	sample = [self chromatogramWithDictionary:sampleElements insertInContext:context path:path error:&contentError];
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
	[sample inferOffScaleChannel];
	
	/// once this is done, we make traces find peaks
	for(Trace *trace in sample.traces) {
		[trace findPeaks];
	}

	return sample;
	
}

/// Converts an ABIF directory entry from big endian to native endian
/// - Parameter entry: The entry to converts.
DirEntry nativeEndianEntry(DirEntry entry) {
	entry.itemNumber = EndianS32_BtoN(entry.itemNumber);
	entry.elementType = EndianS16_BtoN(entry.elementType);
	entry.elementSize = EndianS16_BtoN(entry.elementSize);
	entry.numElements = EndianS32_BtoN(entry.numElements);
	entry.dataSize = EndianS32_BtoN(entry.dataSize);
	if(entry.dataSize > 4) {	/// if the data size is ≤4 bytes, the data is actually the dataOffset member (which must not be interpreted as an int). So we don't change its endianness
		entry.dataOffset = EndianS32_BtoN(entry.dataOffset);
	}
	return entry;
}


/// Returns an object pointed by a directory entry from ABFI file data.
///
/// The method returns nil if no object could be retrieved from the data or if the entry is inconsistent.
/// - Parameters:
///   - entry: The directory entry that points to the item.
///   - fileData: The data containing bytes of the ABIF file.
///   - try: Tells wether the method should try to find an equivalent item at another entry if this entry does not point to decodable data
+ (nullable id)objectForDirEntry:(DirEntry) entry withABIFData:(NSData *)fileData try:(BOOL)try {
																						  
	DirEntry nativeEntry = nativeEndianEntry(entry);
	int32_t dataSize = nativeEntry.dataSize;
	int32_t numElements = nativeEntry.numElements;
	int32_t dataOffset = nativeEntry.dataOffset;
	
	if(dataSize <= 0 || dataSize < numElements * nativeEntry.elementSize  ||
	   (dataSize > 4 && (fileData.length < dataOffset + dataSize || dataOffset < HEADERSIZE))) {
		return nil;
	}
	const char *itemData; 						/// this will point to the item's data.
	id returnedObject = nil;
	
	if(dataSize <= 4) {
		/// if the data size is ≤ 4 bytes, the data is actually the offset of the entry (which, in this case, doesn't represent an offset)
		itemData = (const char *)&dataOffset;
	} else {
		itemData = fileData.bytes + dataOffset;
	}
	
	switch (nativeEntry.elementType) {
		case elementTypePString:
			/// we exclude the first char of a pString (null character)
			itemData++;
		case elementTypeCString:
			/// we exclude the last char of a cString (and reduce the length of the data for a pString, as we have moved the offset by +1 just above)
			/// This is supposed to be a null character, but it seems to vary between samples, which would causes issues down the road (when we compare strings).
			dataSize--;
			/// we return an NSString from the data if the type corresponds to a string
			returnedObject = [[NSString alloc]initWithBytes:itemData length:dataSize encoding:NSASCIIStringEncoding];
			break;
		case elementTypeDate: {
			/// we return an NSString from the data if the type corresponds to a Date (or Time).
			/// Date and time will be converted to a single NSDate afterwards
			if(dataSize != 4) return nil;
			int16_t year = EndianS16_BtoN(*(const int16_t *)itemData);
			returnedObject = [NSString stringWithFormat:@"%hd",year];
			for (int i = 2; i<4; i++) {				/// the other bytes encode the month and day
				returnedObject = [returnedObject stringByAppendingFormat:@"-%hd", itemData[i]];  /// (e.g. "1999-12-23")
			}
			break;
		}
		case elementTypeTime: {
			if(dataSize != 4) {
				return nil;
			}
			/// bytes encode the hour, minutes, seconds (we do not record the hundredths of seconds (fourth byte))
			returnedObject = [NSString stringWithFormat:@"%hd", *itemData];
			for (int i = 1; i<3; i++) {
				returnedObject = [returnedObject stringByAppendingFormat:@":%hd", itemData[i]];
			}
			break;
		}
		/// for the following cases (integers), we convert from Big Endian
		case elementTypeShort:
		case elementTypeWord: {
			/// word is unsigned 16-bit, but we treat is as a short (signed) since no item in the ABIF specs actually uses this type
			if(nativeEntry.elementSize != 2){
				return nil;
			}
			int16_t *converted = bigEndianToNative16((int16_t *)itemData, numElements);
			if(numElements == 1) {
				/// if the data consists in just one number, we return an NSNumber, otherwise an NSData object
				returnedObject = [NSNumber numberWithShort:*converted];
			} else {
				returnedObject = [NSData dataWithBytes:converted length:dataSize];
			}
			free(converted);
			break;
		}
		case elementTypeLong: {
			if(nativeEntry.elementSize != 4) {
				return nil;
			}
			int32_t *converted = bigEndianToNative32((int32_t *)itemData, numElements);
			if(numElements == 1) {
				returnedObject = [NSNumber numberWithInt:*converted];
			} else {
				returnedObject = [NSData dataWithBytes:converted length:dataSize];
			}
			free(converted);
			break;
		}
		default:
			/// if the type is not one we manage, we try to find an equivalent entry (for the same itemName and itemNumber)
			/// This is because HID files store fluorescence data and dye names in two forms: one that is not readable (not documented) and another that is the same as FSA files.
			/// The latter is referenced by entries that are listed in a directory that is not pointed by the header.
			/// In fact, there are many equivalent directories per file (for undocumented reasons).
			/// Some that point to decodable data, some that point to unreadable data
			/// So we look for other entries for the same item to find one that has a known element type
			if(try) {
				returnedObject = [self objectForEntryEquivalentTo:entry inABIFData:fileData];
			}
	}
	
	return returnedObject;
}


/// Finds an returns object based on a directory entry, based on the itemName and itemNumber (and not the offset).
/// Returns nil if a suitable object could not be constructed.
+ (nullable id) objectForEntryEquivalentTo:(DirEntry)entry inABIFData:(NSData *)fileData {
																				
	if(fileData.length < HEADERSIZE + ENTRYSIZE) {
		return nil;
	}
	
	id foundObject = nil;
	
	/// We search for the entry in a range that excludes the header and allow the entry to fit in the file
	NSRange searchRange = NSMakeRange(HEADERSIZE, fileData.length - HEADERSIZE);
	
	/// We search for bytes that constitute the itemName and itemNumber of the entry (8 bytes total), as these two are unique for a given item
	NSData *itemNameAndNumber = [NSData dataWithBytes:&entry length:8];
	while (foundObject == nil) {
		NSRange range = [fileData rangeOfData:itemNameAndNumber options:0 range:searchRange];
		if(range.location == NSNotFound) {
			return nil;
		}
		
		const DirEntry *foundEntry = fileData.bytes + range.location;
		foundObject = [self objectForDirEntry:*foundEntry withABIFData:fileData try:NO];
		if(foundObject == nil) {
			/// If we're here, the entry was not valid or the item element type is not managed
			/// So we search for another entry in the rest of the file
			NSInteger rangeSize = fileData.length - range.location - range.length;
			if(rangeSize < ENTRYSIZE) {
				return nil;
			}
			searchRange = NSMakeRange(range.location + range.length, rangeSize);
		}
	}
	
	return foundObject;
}


/// Returns a chromatogram based on objects in a supplied dictionary, or nil of the dictionary lacks consistent fluorescence data.
///
/// Returns nil and sets the `error`argument if the fluorescence data is inconsistent (missing channel, trace of different lengths, etc.)
/// - Parameters:
///   - sampleContent: The dictionary containing the data to create the chromatogram.
///   - context: The context in which to materialize the chromatogram.
///   - path: The file path of the ABIF file. This is only used to add information to the potential error.
///   - error: On output, any error that prevented creating the file.
+ (nullable instancetype) chromatogramWithDictionary:(NSDictionary *)sampleContent insertInContext:(NSManagedObjectContext *)context path:(NSString *)path error:(NSError **)error  {
	Chromatogram *sample = nil;
	/// we check if the dictionary contains valid data for the traces (the rest is optional)
	/// we will not create a Chromatogram entity otherwise
	/// we will compare the number of data point (scans) per trace. It must be the same
	NSUInteger nScans = [sampleContent[ChromatogramNScansKey] intValue];
	
	/// We create an array that will contain the data necessary to make the traces (5 traces at most)
	NSMutableArray *traceData = [NSMutableArray arrayWithCapacity:5];
	for (int channel = 1; channel <=5; channel++) {
		NSData *fluo = sampleContent[[NSString stringWithFormat:@"rawData%d", channel]];
		NSString *dyeName = sampleContent[[NSString stringWithFormat:@"dye%d", channel]];
		
		if(![fluo isKindOfClass: NSData.class]) {		/// this means that there is no valid data for the corresponding channel
			if(channel < 5 || [dyeName isKindOfClass:NSString.class]) {
				NSString *reason = [NSString stringWithFormat:@"No valid data for fluorescence channel %d.", channel];
				if(error != NULL) {
					*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File %@ was not imported because fluorescence data is missing.", path]
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
				*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File %@ was not imported because fluorescence data is missing.", path]
													suggestion:@""
													  filePath:path
														reason:reason];
			}
			return sample;
			
		}
		
		if(fluo.length / sizeof(int16_t) != nScans) {
			NSString *reason = [NSString stringWithFormat:@"Length of fluorescence data for channel %d (%ld bytes) is inconsistent with the number of reported scans (%ld scans)", channel, fluo.length, nScans];
			if(error != NULL) {
				*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File %@ was not imported because it has inconsistent fluorescence data.", path]
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
	[sampleContent enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
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


/// Converts the n first elements of a big endian 16-bit int array to native and returns the result.
/// - Parameters:
///   - source: The array to convert.
///   - n: The number of element to read from the `source`.
int16_t * bigEndianToNative16 (int16_t *source, long n){
	int16_t *converted = malloc(n*sizeof(int16_t));
	for (long i = 0; i < n; i++) {
		converted[i] = EndianS16_BtoN(source[i]);
	}
	return converted;
}


/// Converts the n first elements of a big endian 32-bit int array to native and returns the result.
/// - Parameters:
///   - source: The array to convert.
///   - n: The number of element to read from the `source`.
int32_t * bigEndianToNative32 (int32_t *source, long n){
	int32_t *converted = malloc(n*sizeof(int32_t));
	for (long i = 0; i < n; i++) {
		converted[i] = EndianS32_BtoN(source[i]);
	}
	return converted;
}


/// Infers the channels that caused saturation and sets the -offscaleRegions attributes
- (void)inferOffScaleChannel {
	if(self.offScaleScans.length == 0) {
		return;
	}
	const int32_t *offscaleScan = self.offScaleScans.bytes;
	long nOffScale = self.offScaleScans.length/sizeof(int);
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
				/// to determine the channel that is off scale, we just see which has higher fluo in the first scan
				/// (not at the tip, as sometimes saturation can truncate a peak)
				const int16_t *rawFluo = trace.rawData.bytes;
				if (rawFluo[currentScan] > maxFluo) {
					maxFluo = rawFluo[currentScan];
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
	
	[self setPrimitiveValue:[NSData dataWithBytes:regions length:count*sizeof(OffscaleRegion)] forKey:ChromatogramOffscaleRegionsKey];
	free(regions);
	
}


# pragma mark - sizing


- (void)applySizeStandard:(SizeStandard *)sizeStandard {
	[self managedObjectOriginal_setSizeStandard:sizeStandard];
	if(sizeStandard) {
		[self managedObjectOriginal_setPolynomialOrder: [NSUserDefaults.standardUserDefaults integerForKey:DefaultSizingOrder]];
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

	float maxSize = (float)DefaultReadLength;	/// will record the max size of a ladder fragment, which we need in case the sizing fails
	int nPoints = 0;
	for(LadderFragment *fragment in trace.fragments) {
		float fragmentSize = fragment.size;
		if(fragmentSize + 50.0 > maxSize) {
			maxSize = fragmentSize + 50.0;
		}
		int scan = fragment.scan;
		if(scan > 0) {
			sizes[nPoints] = fragmentSize;
			scans[nPoints] = scan;
			nPoints++;
		}
	}
	
	int k = self.polynomialOrder +1;

		
	if (nPoints < 4 || nPoints < nFragments/2 || k < 1 || k > 3) {
		[self setLinearCoefsForReadLength:maxSize];
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
		[self setLinearCoefsForReadLength:maxSize];
		return;
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
		}
	}
	
	
//	NSLog(@"offset: %f", maxDiffOffset);
	
	//score = score > 160? 1: score/160;
	[self managedObjectOriginal_setSizingQuality: @(score)];
	
}


-(void)setLinearCoefsForReadLength:(float)readLength {
																	
	float coefs[2] = {0.0, readLength / self.nScans};
	self.coefs = [NSData dataWithBytes: coefs length:2*sizeof(float)];
	
	float reverseCoefs[2] = {-coefs[0]/coefs[1], 1/coefs[1]};
	[self managedObjectOriginal_setReverseCoefs:[NSData dataWithBytes: reverseCoefs length:2*sizeof(float)]];
	[self managedObjectOriginal_setSizingQuality:nil];

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
	
	/// we solve the system Ax = b using LAPACK's sposv, as the A martrix is always symmetric and positive definite
	char uplo = 'U';		/// specifies the lower triangle of the matrix (this doesn't matter since we have filled the whole matrix)
	int nColB = 1;			/// number of columns of b
	sposv_(&uplo, &dim, &nColB, A, &dim, b, &dim, info);		/// results are put in b
	
}


- (float)readLength {
	if(_readLength < 1) {
		[self computeSizes];
	}
	return _readLength;
}


-(void)setReadLength:(float)length {
	_readLength = length > MAX_TRACE_LENGTH ? MAX_TRACE_LENGTH : length;
}


-(void)setStartSize:(float)startSize {
	_startSize = startSize > 0.0 ? 0.0 : startSize;
}


- (NSData *)sizes {
	if(_sizes.length == 0) {
		if(!self.coefs) {
			[self computeFitting];		/// this method modifies core data attribute, hence may generate undo actions that may not be desirable. This is why we compute sizing coeffcients on sample import.
		}
		[self computeSizes];
	}
	return _sizes;
}


-(void)setSizes:(NSData * )sizes {
	BOOL hadSizes = _sizes.length > 0;
	_sizes = sizes;
	/// if sizes have changed, allele sizes must be changed as well
	if(hadSizes && sizes) {
		for (Genotype *genotype in self.genotypes) {
			for(Allele *allele in genotype.alleles) {
				[allele setSize];
			}
		}
	}
}


/// Resets the size in response to a change in sizing.
-(void)updateSizes {
	self.sizes = NSData.new;
	NSUndoManager *manager = self.managedObjectContext.undoManager;
	if(manager.canUndo || manager.canRedo) {
		[manager registerUndoWithTarget:self selector:@selector(updateSizes) object:nil];
	}
	
}

/// Computes and sets the `size` attribute.
- (void)computeSizes {
	
	if(self.nScans == 0 || self.coefs.length == 0) {
		self.readLength = DefaultReadLength;
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
	const float *a = self.coefs.bytes;
	NSInteger order = self.coefs.length / sizeof(float);
	for (int n = 0; n < order; n++) {
		float exponent = n;						/// we will raise scans to the power of n
		vDSP_vfill(&exponent, exponents, 1, nScans);
		
		/// so we can use this accelerated function (I couldn't find one in Accelerate that uses a scalar for exponent)
		vvpowf(scan2power, exponents, scans, &nScans);
		vDSP_vsmul(scan2power, 1, &a[n], scan2power, 1, nScans);
		vDSP_vadd(computedSizes, 1, scan2power, 1, computedSizes, 1, nScans);
	}
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
	
	self.sizes =[NSData dataWithBytes:computedSizes length:nScans * sizeof(float)];
	
	free(scans);
	free(computedSizes);
	free(exponents);
	free(scan2power);
}


- (int)maxScan {
	if(_maxScan == 0) {
		[self computeSizes];
	}
	return _maxScan;
}


- (float)sizeForScan:(int)scan {
	if(!self.coefs) {
		[self computeFitting];
		if(!self.coefs) {
			return -1;
		}
	}
	return yGivenPolynomial(scan, self.coefs.bytes, (int)self.coefs.length/sizeof(float));
}


- (int)scanForSize:(float)size {
	if(!self.reverseCoefs) {
		[self computeFitting];
		if(!self.reverseCoefs || !self.coefs) {
			return -1;
		}
	}
	int scan = yGivenPolynomial(size, self.reverseCoefs.bytes, (int)self.reverseCoefs.length/sizeof(float));
	
	/// the scan returned may not be the closest to the size, as the revese coefs do not do the exact reverse of what the coefs do (which is expected)
	/// but as this scan should be close to the scan we want, we find it by iteration
	const float *sizes = self.sizes.bytes;
	long nScans = self.sizes.length/sizeof(float);
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


- (void)setBoundSizeStandard:(SizeStandard *)sizeStandard {
	[self applySizeStandard:sizeStandard];
	[self.managedObjectContext.undoManager setActionName:@"Apply Size Standard"];
}


- (SizeStandard *)boundSizeStandard {
	return self.sizeStandard;
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



- (void)setSampleName:(NSString *)sampleName {
	[self managedObjectOriginal_setSampleName:sampleName];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName: @"Rename Sample"];
	}
}


- (void)setSampleType:(NSString *)sampleType {
	[self managedObjectOriginal_setSampleType:sampleType];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName: @"Edit Sample Type"];
	}
}


- (void)setComment:(NSString *)comment {
	[self managedObjectOriginal_setComment:comment];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName: @"Edit Sample Comment"];
	}
}


- (void)setPolynomialOrder:(PolynomialOrder)polynomialOrder {
	if(polynomialOrder < -1 || polynomialOrder > 3 || polynomialOrder == self.polynomialOrder) {
		return;
	}
	[self managedObjectOriginal_setPolynomialOrder:polynomialOrder];
	
	if(!self.deleted) {
		[self computeFitting];
		[self.managedObjectContext.undoManager setActionName:@"Change Fitting Method"];
	}
}
/*
- (void)applyFitting:(NSNumber *)polynomialOrder {
	self.polynomialOrder = polynomialOrder;
	[self computeSizing];
}  */



-(void)applyPanelWithAlleleName:(NSString *)alleleName {
	[self managedObjectOriginal_setGenotypes:nil];		/// we remove genotypes we may have from a previous panel (genotypes delete themselves when they lose their sample)
	if (self.panel) {
		for (Mmarker *marker in self.panel.markers) {
			Genotype *newGenotype = [[Genotype alloc] initWithMarker:marker sample:self];
			if(!newGenotype) {
				NSLog(@"%@", [NSString stringWithFormat:@"failed to add genotype for marker %@ and sample %@", marker.name, self.sampleName ]);
			} else {
				for(Allele *allele in newGenotype.alleles) {
					[allele managedObjectOriginal_setName:alleleName];
				}
			}
		}
	}
	self.panelVersion = self.panel.version.copy;
}


- (void)setCoefs:(NSData *)coefs {
	[self managedObjectOriginal_setCoefs:coefs];
	[self updateSizes];
	/// when sizing has changed, we note that any genotype may be checked
	for(Genotype *genotype in self.genotypes) {
		genotype.status =genotypeStatusSizingChanged;
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
	if(name.length == 0) {
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


- (BOOL)validatePanel:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	/// we do not validate a panel if we lack channel used by markers
	Panel *panel = *value;
	if(panel) {
		for(Mmarker *marker in panel.markers) {
			Trace *trace = [self traceForChannel:marker.channel];
			if(!trace || trace.isLadder) {
				if (error != NULL) {
					NSString *reason = [NSString stringWithFormat:@"The chromatogram lacks adequate data for the %@ channel, required by marker '%@'.", colors[marker.channel], marker.name];
					*error = [NSError managedObjectValidationErrorWithDescription:[NSString stringWithFormat:@"Panel '%@' cannot be applied to sample '%@' because the sample lacks a required channel.", panel.name, self.sampleName]
																	   suggestion:@""
																		   object:self
																		   reason:reason];
				}
				return NO;
			}
		}
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

- (void)encodeWithCoder:(NSCoder *)coder {		/// we encode all relationships, except the parent folder. This relationship is already covered (in the opposite direction) by the sample folder when it is encoded
	NSProgress *currentProgress = NSProgress.currentProgress;
	if(currentProgress.isCancelled) {
		return;
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
		[self managedObjectOriginal_setPanel: [coder decodeObjectOfClass:Panel.class forKey:ChromatogramPanelKey]];	/// it is important to decode the panel first, as it may be replaced by one already in the store
		[self setPrimitiveValue:self.panel.version.copy forKey:@"panelVersion"]; /// the panel that is decoded may not be the one we had, but an equivalent one present in the store with a different version. We use its version.
		[self managedObjectOriginal_setSizeStandard: [coder decodeObjectOfClass:SizeStandard.class forKey:ChromatogramSizeStandardKey]];
		[self managedObjectOriginal_setTraces: [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Trace.class, nil] forKey:ChromatogramTracesKey]];
		[self managedObjectOriginal_setGenotypes: [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Genotype.class, nil]  forKey:ChromatogramGenotypesKey]];
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
	return @[ChromatogramPasteboardType];
}


- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard {
	if([type isEqualToString:ChromatogramPasteboardType]) {
		/// we don't write a chromatogram to the pasteboard, we only write it when required (upon paste)
		return NSPasteboardWritingPromised;
	}
	return 0;
}


- (id)pasteboardPropertyListForType:(NSPasteboardType)type {
		
	if([type isEqualToString:ChromatogramPasteboardType]) {
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
	return nil;
}


@end
