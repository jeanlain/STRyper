//
//  ABIFparser.m
//  STRyper
//
//  Created by Jean Peccoud on 04/11/2023.
//

#import "ABIFparser.h"
#import "NSError+NSErrorAdditions.h"

@implementation ABIFparser



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
typedef NS_ENUM(int16_t, elementType) {
	elementTypeWord = 3,				/// an unsigned 16-bit int
	elementTypeShort = 4,				/// signed 16-bit int
	elementTypeLong = 5,				/// a 32-bit int ("Long" is misleading)
	elementTypeDate = 10,
	elementTypeTime = 11,
	elementTypePString = 18,
	elementTypeCString = 19
} ;

static const int entrySize = 20; 	/// the size of a DirentryEntry in bytes
static const int headerSize = 34;   /// the size of an ABIF file header in bytes
								   
								   

+(NSDictionary *)dictionaryWithABIFile:(NSString *)path itemsToImport:(NSDictionary *)itemsToImport error:(NSError **)error {
	NSString *corruptFileString = [NSString stringWithFormat:@"File '%@' could not be decoded.", path];
	
	NSError *readError = nil;
	NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath: path error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return nil;
	}
	
	if( [attributes fileSize] > 1e7) {
		/// We avoid reading a file that is too big
		if (error != NULL){
			NSString *description = [NSString stringWithFormat:@"File '%@' is too large.", path];
			*error = [NSError errorWithDomain:STRyperErrorDomain
										 code:NSFileReadTooLargeError
									 userInfo:@{
				NSLocalizedDescriptionKey: description,
				NSLocalizedRecoverySuggestionErrorKey: @"Check that the file is a chromatogram file.",
				NSFilePathErrorKey: path
			}];
		}
		return nil;
	}
	
	NSData *fileData = [NSData dataWithContentsOfFile:path options:NSDataReadingMapped error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return nil;
	}
	
	if(fileData.length < headerSize) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"File size of %ld bytes is less than expected header size of %d bytes.", fileData.length, headerSize];
			*error = [NSError fileReadErrorWithDescription:corruptFileString
												suggestion:@""
												  filePath:path
													reason:reason];
		}
		return nil;
	}
	
	/// We check it is a supported file type "ABIF" (the first bytes of the file)
	const char *fileBytes = fileData.bytes;
	if(strncmp(fileBytes, "ABIF", 4) != 0) {
		if (error != NULL) {
			NSString *code = [[NSString alloc] initWithBytes:fileBytes length:4 encoding:NSASCIIStringEncoding];
			NSString *reason = [NSString stringWithFormat:@"Header '%@' does not correspond to expected header 'ABIF'.", code];
			*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File '%@' is not recognized as a chromatogram file.", path]
												suggestion:@""
												  filePath:path
													reason:reason];
		}
		return nil;
	}
	
	/// We check the ABIF version, which is stored as a short after the first 4 bytes
	int16_t version = EndianS16_BtoN(*(const int16_t *)(fileBytes + 4));
	if(version >= 400 || version < 100) {
		/// 4.00 is arbitrary. Specs of version ≥ 1.0x are not public, there is no guaranty to import the file correctly.
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"File version %.01f is unsupported (min supported: 1.00, max supported: 4.00)", (float)version/100];
			*error = [NSError fileReadErrorWithDescription:[NSString stringWithFormat:@"File '%@' ABIF version is not supported by this application.", path]
												suggestion:@""
												  filePath:path
													reason:reason];
		}
		return nil;
	}
	
	/// We read the file's first entry that lists the directory's contents, and is at byte 6
	DirEntry headerEntry = *(const DirEntry *)(fileBytes + 6);
	headerEntry = nativeEndianEntry(headerEntry);
	/// The header entry indicates the number of directory entries and their location. We check if this is consistent.
	if(headerEntry.dataSize < headerEntry.numElements * sizeof(DirEntry) ||
	   (fileData.length < headerEntry.dataOffset + headerEntry.dataSize) || headerEntry.dataOffset < headerSize) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"File size of %ld bytes is too short given the offset of the directory entry (offset %d).", fileData.length, headerEntry.dataOffset + headerEntry.dataSize];
			*error = [NSError fileReadErrorWithDescription:corruptFileString
												suggestion:@""
												  filePath:path
													reason:reason];
			return nil;
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
				return nil;	/// We return upon the first error
			} else {
				sampleElements[attributeName] = object;
			}
		}
	}
	return [NSDictionary dictionaryWithDictionary:sampleElements];
}



/// Converts an ABIF directory entry from big endian to native endian
/// - Parameter entry: The entry to convert.
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
///   - try: Tells wether the method should try to find an equivalent item at another entry if this entry does not point to decodable data.
+ (nullable id)objectForDirEntry:(DirEntry) entry withABIFData:(NSData *)fileData try:(BOOL)try {
																						  
	DirEntry nativeEntry = nativeEndianEntry(entry);
	int32_t dataSize = nativeEntry.dataSize;
	int32_t numElements = nativeEntry.numElements;
	int32_t dataOffset = nativeEntry.dataOffset;
	
	if(dataSize <= 0 || dataSize < numElements * nativeEntry.elementSize  ||
	   (dataSize > 4 && (fileData.length < dataOffset + dataSize || dataOffset < headerSize))) {
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
			if(dataSize != 4) {
				return nil;
			}
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
			/// In fact, there are many equivalent directories per file (for undocumented reasons),
			/// some that point to decodable data, some that point to unreadable data
			/// So we look for other entries for the same item to find one that has a known element type
			if(try) {
				returnedObject = [self objectForEntryEquivalentTo:entry inABIFData:fileData];
			}
	}
	
	return returnedObject;
}


/// Finds an returns object based on a directory entry, using its itemName and itemNumber (and not the offset).
/// Returns `nil` if no suitable object could be found.
/// - Parameters:
///   - entry: The entry describing the object.
///   - fileData: The data containing the ABIF file.
+ (nullable id) objectForEntryEquivalentTo:(DirEntry)entry inABIFData:(NSData *)fileData {
																				
	if(fileData.length < headerSize + entrySize) {
		return nil;
	}
	
	id foundObject = nil;
	
	/// We search for the entry in a range that excludes the header and allows the entry to fit in the file
	NSRange searchRange = NSMakeRange(headerSize, fileData.length - headerSize);
	
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
			if(rangeSize < entrySize) {
				return nil;
			}
			searchRange = NSMakeRange(range.location + range.length, rangeSize);
		}
	}
	
	return foundObject;
}


/// Converts the n first elements of a big endian 16-bit int array to native and returns the result.
///
/// IMPORTANT: the result array is allocated on the heap and must be freed.
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
///
/// IMPORTANT: the result array is allocated on the heap and must be freed.
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


@end
