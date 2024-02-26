//
//  Panel.m
//  STRyper
//
//  Created by Jean Peccoud on 13/02/2022.
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



#import "Panel.h"
#import "Mmarker.h"
#import "Bin.h"
#import "PanelFolder.h"



@interface Panel (DynamicAccessors)

-(NSSet *)managedObjectOriginal_markers;
-(void)managedObjectOriginal_setMarkers: (NSSet *)markers;
-(void)managedObjectOriginal_setSamples: (NSSet *)samples;

@end


static void * const markersChangedContext = (void*)&markersChangedContext;
static void * const samplesChangedContext = (void*)&samplesChangedContext;

NSArray *sortedByStart;

/// global variables use during panel import from a text file
NSArray const * _Nonnull channelColorNames;	/// channel color names in the order used through the app
static NSString *fileErrorSuggestion;		/// a generic suggestion in case of error during import.
static NSDictionary *fieldDescription;		/// describe the field of a text file that describes a panel
static NSNumberFormatter *numberFormatter;	/// a number formatter used during panel decoding from a text file
											
NSString * _Nonnull const PanelMarkersKey = @"markers";
NSString * _Nonnull const PanelSamplesKey = @"samples";

@implementation Panel

@dynamic markers, samples;

+ (void)initialize {
	fileErrorSuggestion = @"Check the file. Encoding must be ASCII or UTF-8 and fields separated by tabs";
	
	/// This dictionary describes a line in the text file describing elements of a panel.
	/// The key is the keyword in the first field of the line.
	/// The value contains the class of the described object, followed by the keys that the other fields specify for the object.
	fieldDescription = @{
		@"panel": @[Panel.entity.name, @"name"],
		@"marker": @[Mmarker.entity.name, @"name", @"start", @"end", @"channel", @"ploidy", @"motiveLength"],
		@"bin": @[Bin.entity.name, @"name", @"start", @"end"],
	};
	
	/// the colors corresponding to channels, as the text file specifies color names. The index of the color in the array is the channel
	channelColorNames = @[@"blue", @"green", @"black", @"red", @"orange"];
	
	numberFormatter = NSNumberFormatter.new;	/// a formatter we use during import
	numberFormatter.decimalSeparator = @".";
	
}

- (NSString *)folderType {
	return @"Panel";
}


- (Class)parentFolderClass {
	return PanelFolder.class;
}


- (BOOL)isPanel {
	return YES;
}


- (BOOL)canTakeSubfolders {
	return NO;
}



- (NSString *)stringRepresentation {
	NSMutableString *exportString = NSMutableString.new;
	/// a panel description stats with the keyword "panel" and just specifies its name
	[exportString appendString:[NSString stringWithFormat:@"panel\t%@\n", self.name]];
	for(Mmarker *marker in self.markers) {
		/// for each marker, we use the "marker" keyword and specify all relevant properties
		[exportString appendString:marker.stringRepresentation];
		for(Bin *bin in marker.bins) {
			/// for each bin, the keyword is "bin"
			[exportString appendString:bin.stringRepresentation];
		}
	}
	return exportString;
}


+(NSError *)panelReadErrorWithFileName:(NSString *)fileName Errors:(NSArray <NSError *> *)errors {
	NSString *errorDescription = [NSString stringWithFormat:@"File '%@' could not be imported due to errors.", fileName.lastPathComponent];
	NSString *suggestion = @"Please, check the expected file format in the application user guide.";

	NSDictionary *userInfo = @{NSLocalizedDescriptionKey : errorDescription,
							   NSLocalizedRecoverySuggestionErrorKey : suggestion,
							   NSDetailedErrorsKey : errors};
							   
	
	NSError *error = [[NSError alloc] initWithDomain:STRyperErrorDomain code:NSFileReadUnsupportedSchemeError userInfo:userInfo];
	return error;
}


+ (nullable instancetype) panelFromTextFile:(NSString *)path insertInContext:(NSManagedObjectContext *)managedObjectContext error:(NSError *__autoreleasing  _Nullable *)error{
	/// the format of the text file is the same as that generated during export (obviously), see -stringRepresentation.
	

	NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath: path error:nil];
	if( attributes.fileSize > 1e6) {
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat:@"File '%@' is too large.", path];
			*error = [NSError errorWithDomain:STRyperErrorDomain
										 code:NSFileReadTooLargeError
									 userInfo:@{
				NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
				NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Check that the file describes a panel.", nil),
				NSFilePathErrorKey: path
			}];
		}
	
		return nil;
	}
	
	NSError *readError = nil;
	NSString *panelString = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return nil;
	}
	
	/// Will contain errors founds, to report as many as possible to the user, so they can correct all without retrying.
	NSMutableArray *errors = NSMutableArray.new;
	
	/// As we list most encountered errors, we need to known which have already been encountered.
	/// This avoid reporting irrelevant errors
	int unknownFieldErrors = 0,
	numberOfFieldsErrors = 0,
	severalPanelsErrors = 0,
	panelParseErrors = 0,
	markerParseErrors = 0,
	noPanelErrors = 0,
	noMarkerErrors = 0;
	
	
	/// we prepare pointers to entities that will be created at each row of the file (one row = one object)
	Panel *panel;
	Mmarker *marker;
	Bin *bin;
	
	NSArray *lines = [panelString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSMutableArray *fields = [NSMutableArray arrayWithCapacity:lines.count];
	for (NSString *row in lines) {
		/// fields are separated by tabulations.
		[fields addObject:[row componentsSeparatedByString:@"\t"]];
	}
	int line = 0;			/// the line number is used to show the user which line is problematic in case of failure
	for (NSArray *columns in fields) {
		line++;
		
		/// We identify the entity described in the line
		NSString *type = [columns.firstObject stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet].lowercaseString;
		
		if(type.length == 0 && columns.count == 1) {
			/// we skip any empty line
			continue;
		}
		if(![fieldDescription.allKeys containsObject:type]) {
			unknownFieldErrors ++;
			NSString *reason = [NSString stringWithFormat:@"Line %d: unrecognized value '%@' in first column.", line, type];
			NSError *theError = [NSError fileReadErrorWithDescription:reason
													suggestion:@"The first column must contain either 'panel', 'marker' or 'bin'."
													  filePath:path
														reason:reason];
			[errors addObject:theError];
			
			if(unknownFieldErrors == 10) {
				/// At this stage, the file is probably not describing a panel
				if(error != NULL) {
					*error = [self panelReadErrorWithFileName:path Errors:errors];
				}
				return nil;
			}
			continue;
		}
		
		
		long numExpectedFields = [fieldDescription[type] count];
		if(columns.count < numExpectedFields) {
			numberOfFieldsErrors++;
			NSString *reason = [NSString stringWithFormat:@"Line %d: was expecting %ld columns for %@ description, but found %ld.", line, numExpectedFields, type, columns.count];
			NSError *theError  = [NSError fileReadErrorWithDescription:reason
													suggestion:fileErrorSuggestion
													  filePath:path
														reason:reason];
			[errors addObject:theError];
			continue;
		}
		
		NSArray *retainedFields = [columns objectsAtIndexes: [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, numExpectedFields-1)]];
		
		/// We create an object (Panel, Marker or Bin) for the current line
		NSError *parseError = nil;
		NSManagedObject *obj = [self entityForType:type withFields:retainedFields insertInContext:managedObjectContext error:&parseError line:line];
		if(parseError) {
			if([type isEqualToString:@"panel"]) {
				panelParseErrors++;
			} else if([type isEqualToString:@"marker"]) {
				markerParseErrors++;
			}
			[errors addObject:parseError];
			continue;
		}
		
		if([obj isKindOfClass: Panel.class]) {
			if(panel != nil) {
				severalPanelsErrors++;
				NSString *reason = [NSString stringWithFormat:@"Line %d: A panel is already described.", line];
				NSError *theError = [NSError fileReadErrorWithDescription:reason
														suggestion:@"The file must describe no more than one panel. The keyword 'Panel' must appear only at the first line in the first column."
														  filePath:path
															reason:reason];
				[errors addObject:theError];
				continue;
			}
			panel = (Panel *)obj;
		
		} else if ([obj isKindOfClass: Mmarker.class]) {
			if(!panel) {
				if (!panelParseErrors && !noPanelErrors && !numberOfFieldsErrors && !unknownFieldErrors) {
					noPanelErrors++;
					markerParseErrors++;
					/// We report that a marker is described before the panel only if some errors were not reported before.
					/// We won't complain that a panel has not been described if the user only made a typo in the line describing it.
					/// And we won't report it for each marker
					NSString *reason = [NSString stringWithFormat:@"Line %d: A marker is described before the panel.", line];
					NSError *theError = [NSError fileReadErrorWithDescription:reason
														suggestion:@"The panel must be described at the first line."
														  filePath:path
															reason:reason];
					[errors addObject:theError];
				}
				continue;
			}
			marker = (Mmarker *) obj;
			[marker managedObjectOriginal_setPanel:panel];
			
		} else if ([obj isKindOfClass: Bin.class]) {
			if(!marker) {
				if (!markerParseErrors && !noMarkerErrors && !numberOfFieldsErrors && !unknownFieldErrors) {
					/// Same as above: we only complain that a marker has not been described if we can make sure that the line was forgotten, and we only do it once.
					noMarkerErrors = YES;
					NSString *reason = [NSString stringWithFormat:@"Line %d: A bin is described before any marker.", line];
					NSError *theError = [NSError fileReadErrorWithDescription:reason
														suggestion:@"The second line must be a marker description."
														  filePath:path
															reason:reason];
					
					[errors addObject:theError];
				}
				continue;
			}
			bin = (Bin *)obj;
			[bin managedObjectOriginal_setMarker:marker];
		}
		
		/// We validate the created object if no error occurred before (otherwise, validation may be irrelevant).
		if(!unknownFieldErrors && !numberOfFieldsErrors && !severalPanelsErrors && !noPanelErrors && !panelParseErrors && !markerParseErrors && !noMarkerErrors) {
			NSError *validationError;
			if(![obj isKindOfClass: Panel.class]) {
				/// we don't validate the panel because it is not in its final destination
				[obj validateForUpdate:&validationError];
			}
			if(validationError) {
				NSArray *validationErrors = (validationError.userInfo)[NSDetailedErrorsKey];
				if(!validationErrors) {
					validationErrors = @[validationError];
				} else {
					validationErrors = [validationErrors valueForKeyPath:@"@distinctUnionOfObjects.self"];
				}
				
				for(NSError *theError in validationErrors) {
					NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:theError.userInfo];
					
					NSString *description = [NSString stringWithFormat:@"Line %d: %@", line, userInfo[NSLocalizedDescriptionKey]];
					[userInfo setValue:description forKey:NSLocalizedDescriptionKey];
					[errors addObject: [NSError errorWithDomain:theError.domain code:theError.code userInfo:userInfo]];
				}
			}
		}
	}
	
	if(errors.count > 0) {
		if(error != NULL) {
			if(errors.count == 1) {
				*error = errors.firstObject;
			} else {
				*error = [self panelReadErrorWithFileName:path Errors:errors];
			}
		}
		return nil;
	}
	
	return panel;
}


/// Generate an entity (Panel, Marker or Bin) corresponding to a line containing fields
+ (NSManagedObject *)entityForType:(NSString *)type withFields:(NSArray <NSString *>*)fields insertInContext:(NSManagedObjectContext *)MOC error:(NSError *__autoreleasing *)error line:(int)line {
	
	NSArray *keys =  fieldDescription[type];
	NSString *entityName = keys.firstObject;
	NSManagedObject *obj = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:MOC];
	
	for (int i = 0; i < fields.count; i++) {
		NSString *field = fields[i];
		if(field.length == 0) {
			if (error != NULL) {
				NSString *reason = [NSString stringWithFormat:@"Line %d: column %d is empty.", line, i];
				*error = [NSError fileReadErrorWithDescription:reason
													suggestion:fileErrorSuggestion
													  filePath:@""
														reason:reason];
			}
			return obj;
		}
		NSString *key = keys[i+1];
		if (i > 0) {		/// columns > 2 always represent numbers
			NSNumber *num;
			if(i==3) {		/// channel is a number, but is specified as a string (color)
				field = [field stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
				NSUInteger channel = [channelColorNames indexOfObject:field];
				if(channel == NSNotFound) {
					if (error != NULL) {
						NSString *reason = [NSString stringWithFormat:@"Line %d, column %d: dye color is not recognized.", line, i+2];
						*error = [NSError fileReadErrorWithDescription:reason
															suggestion:@"This column must contain either 'blue', 'green', 'black, 'red' or 'orange'"
															  filePath:@""
																reason:reason];
					}

					return obj;
				}
				num = @(channel);
			} else {
				num = [numberFormatter numberFromString:field];
				if(num == nil) {
					if (error != NULL) {
						NSString *reason = [NSString stringWithFormat:@"Line %d, column %d: a number was expected for %@ of %@.", line, i+2, key, type];
						*error = [NSError fileReadErrorWithDescription:reason
															suggestion:@"Check this value. Note that decimal separators must be periods '.'"
															  filePath:@""
																reason:reason];
					}
					return obj;
				}
			}
			if(i <= 2) {	/// the first numbers always represent start end end coordinates, and are floats
				num = @(num.floatValue);
			} else {		/// else numbers are integer (short)
				num = @(num.shortValue);
			}
			[obj setPrimitiveValue:num forKey:key];
		} else {
			[obj setPrimitiveValue:field forKey:key];
		}
	}
	
	return obj;

}


- (NSString *)proposedMarkerName {
	int i = 1;
	BOOL ok = YES;
	NSString *candidateName = @"Marker";
	do {
		candidateName = [NSString stringWithFormat:@"Marker %d", i];
		for (Mmarker *marker in self.markers) {
			if([candidateName isEqualToString:marker.name]) {
				ok = NO;
				break;
			} else ok = YES;
		}
		i++;
	} while(!ok);
	return candidateName;
	
}



- (NSArray *)markersForChannel:(ChannelNumber)channel {
	return [self.markers.allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Mmarker *marker, NSDictionary<NSString *,id> * _Nullable bindings) {
		return marker.channel == channel;
	}]];
}



+(BOOL)supportsSecureCoding {
	return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder {
	[super encodeWithCoder:coder];
	if(self.parent.parent) {
		/// we do not encode the root folder (which has no parent and is invisible to the user)
		[coder encodeObject:self.parent forKey:@"parent"];
	}
	[coder encodeObject:self.markers forKey:@"markers"];
}



- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		self.markers = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Mmarker.class, nil]  forKey:@"markers"];
		self.parent = [coder decodeObjectOfClass:PanelFolder.class forKey:@"parent"];
	}
	return self;
}



- (BOOL)isEquivalentTo:(__kindof NSManagedObject *)obj {
	if(obj.class != self.class) {
		return NO;
	}
	/// to test for equivalence, we don't compare all our attributes.
	Panel *panel = obj;
	if(![panel.name isEqualToString:self.name]) {
		return NO;		/// we must have equivalent names and markers
	}
	if(panel.markers.count != self.markers.count) {
		return NO;
	}
	if(panel.markers.count == 0 && self.markers.count == 0) {
		return YES;
	}
	
	NSArray *markers = [self.markers sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] ;
	NSArray *existingMarkers = [panel.markers sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] ;
	
	for (int i = 0; i < markers.count; i++) {
		if(![markers[i] isEquivalentTo:existingMarkers[i]]) {
			return NO;
		}
	}
	return YES;
}

@end
