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
#import "NSArray+NSArrayAdditions.h"



@interface Panel (DynamicAccessors)

-(NSSet *)managedObjectOriginal_markers;
-(void)managedObjectOriginal_setMarkers: (NSSet *)markers;
-(void)managedObjectOriginal_setSamples: (NSSet *)samples;

@end


static void * const markersChangedContext = (void*)&markersChangedContext;
static void * const samplesChangedContext = (void*)&samplesChangedContext;

@implementation Panel

@dynamic markers, samples;


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


- (NSArray *)panels {
	return @[self];
}


- (NSString *)exportString {
	NSMutableArray *exportStrings = NSMutableArray.new;
	[exportStrings addObject:[NSString stringWithFormat:@"panel\t%@", self.name]];
	NSArray *sortedMarkers = [self.markers.allObjects sortedArrayUsingKey:@"name" ascending:YES];
	for(Mmarker *marker in sortedMarkers) {
		/// for each marker, we use the "marker" keyword and specify all relevant properties
		[exportStrings addObject:marker.stringRepresentation];
		NSArray *sortedBins = [marker.bins.allObjects sortedArrayUsingKey:@"start" ascending:YES];
		NSArray *binStrings = [sortedBins valueForKeyPath:@"@unionOfObjects.stringRepresentation"];
		if(binStrings.count > 0) {
			[exportStrings addObjectsFromArray:binStrings];
		}
	}
	return [[exportStrings componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}


- (BOOL)takeBinSetFromGenemapperFile:(NSString *)path error:(NSError *__autoreleasing  _Nullable *)error {
	
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
		
		return NO;
	}
	
	NSError *readError = nil;
	NSString *binSetString = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return NO;
	}
	
	binSetString = [binSetString stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	
	/// Will contain errors founds, to report as many as possible to the user, so they can correct all without retrying.
	NSMutableArray *errors = NSMutableArray.new;
	
	int unknownMarkerErrors = 0;
	BOOL markerFound = NO,
	binFound = NO,
	panelFound = NO;
	
	NSArray *lines = [binSetString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSMutableArray *fields = [NSMutableArray arrayWithCapacity:lines.count];
	for (NSString *row in lines) {
		/// fields are separated by tabulations.
		[fields addObject:[row componentsSeparatedByString:@"\t"]];
	}
	
	Mmarker *currentMarker;
	
	int line = 0;			/// the line number is used to show the user which line is problematic in case of failure
	for (NSArray *columns in fields) {
		
		line++;
		NSString *firstField = [columns.firstObject stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet].lowercaseString;
		if([firstField rangeOfString:@"#"].location == 0) {
			continue;
		}
		
		if(firstField.length == 0 && columns.count == 1) {
			/// we skip any empty line
			continue;
		}
		
		if([firstField isEqualToString:@"panel name"]) {
			if(panelFound) {
				if(error != NULL) {
					NSString *reason = @"The file contains bins from several marker panels.";
					*error = [NSError fileReadErrorWithDescription:reason
														suggestion:@"Only bins from a single marker panel can be imported."
														  filePath:path
															reason:reason];
				}
				return NO;
			}
			panelFound = YES;
		}
		
		if([firstField isEqualToString:@"marker name"]) {
			currentMarker = nil;
			NSString *markerName = @"";
			
			if(columns.count >= 2) {
				markerName = columns[1];
				for(Mmarker *marker in self.markers) {
					if([marker.name isEqualToString:markerName]) {
						currentMarker = marker;
						marker.bins = nil;
						markerFound = YES;
						break;
					}
				}
			}
			
			if(!currentMarker) {
				unknownMarkerErrors++;
				NSError *anError;
				if(markerName.length > 0) {
					NSString *reason = [NSString stringWithFormat:@"Line %d: marker '%@' is not in panel '%@'.", line, markerName, self.name];
					anError = [NSError fileReadErrorWithDescription:reason
														suggestion:@"Please check the marker name."
														  filePath:path
															reason:reason];
				} else {
					NSString *reason = [NSString stringWithFormat:@"Line %d: marker name is missing.", line];
					anError = [NSError fileReadErrorWithDescription:reason
														suggestion:@"Please specify the marker name in the second column"
														  filePath:path
															reason:reason];
				}
				[errors addObject:anError];
			}
		} else {
			if(currentMarker) {
				NSError *binError;
				Bin *bin = [self binWithGenemapperFields:columns atLine:line ofFile:path error:&binError];
				if(binError) {
					[errors addObject:binError];
				} else {
					[bin managedObjectOriginal_setMarker:currentMarker];
					[bin validateForUpdate:&binError];
					if(binError) {
						NSArray *validationErrors = (binError.userInfo)[NSDetailedErrorsKey];
						if(!validationErrors) {
							validationErrors = @[binError];
						} else {
							validationErrors = [validationErrors valueForKeyPath:@"@distinctUnionOfObjects.self"];
						}
						
						for(NSError *theError in validationErrors) {
							NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:theError.userInfo];
							
							NSString *description = [NSString stringWithFormat:@"Line %d: %@", line, userInfo[NSLocalizedDescriptionKey]];
							[userInfo setValue:description forKey:NSLocalizedDescriptionKey];
							[errors addObject: [NSError errorWithDomain:theError.domain code:theError.code userInfo:userInfo]];
						}
					} else {
						binFound = YES;
					}
				}
			}
		}
	}
	
	if(errors.count > 0 && error != NULL) {
		if(errors.count == 1) {
			*error = errors.firstObject;
		} else {
			*error = [NSError fileReadErrorWithFileName:path Errors:errors];
		}
	} else if(!markerFound) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"No marker was found."];
			*error = [NSError fileReadErrorWithDescription:reason
												suggestion:@"Verify that 'Marker Name' appears at the beginning of a line."
												  filePath:path
													reason:reason];
		}
	} else if(!binFound && error != NULL) {
		NSString *reason = [NSString stringWithFormat:@"No bin was found."];
		*error = [NSError fileReadErrorWithDescription:reason
											suggestion:@"Check that there are lines describing bins after the line describing a marker."
											  filePath:path
												reason:reason];
	}
	return errors.count == 0;
}


- (Bin *)binWithGenemapperFields:(NSArray<NSString *> *)fields atLine:(int) line ofFile:(NSString *)path error:(NSError **)error {
	if(fields.count < 4) {
		NSString *reason = [NSString stringWithFormat:@"Line %d: insufficient number of fields", line];
		if(error != NULL) {
			*error = [NSError fileReadErrorWithDescription:reason
												suggestion:@"A bin description requires ≥4 columns, as per Genemapper format."
												  filePath:path
													reason:reason];
		}
		return nil;
	}
	
	NSString *binName = [fields.firstObject stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet];
	if(binName.length == 0) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"Line %d: bin name is missing.", line];
			*error = [NSError fileReadErrorWithDescription:reason
												suggestion:@"Please specify the bin name in the first column"
												  filePath:path
													reason:reason];
		}
		return nil;
	}
	
	NSNumberFormatter *numberFormatter = NSNumberFormatter.new;
	numberFormatter.decimalSeparator = @".";

	NSMutableArray<NSNumber *> *numbers = [NSMutableArray arrayWithCapacity:3];
	for(int i = 1; i < 4; i++) {
		NSString *field = fields[i];
		NSNumber *num = [numberFormatter numberFromString:field];
		if(num == nil) {
			if(error != NULL) {
				NSString *reason = [NSString stringWithFormat:@"Line %d, column %d: a number was expected.", line, i+1];
				*error = [NSError fileReadErrorWithDescription:reason
													suggestion:@"Check this value. Note that decimal separators must be periods '.'"
													  filePath:path
														reason:reason];
			}
			return nil;
		}
		[numbers addObject:num];
	}
	
	Bin *bin = [[Bin alloc] initWithContext:self.managedObjectContext];
	bin.name = binName;
	float mid = fabs(numbers.firstObject.floatValue);
	bin.start = mid - fabs(numbers[1].floatValue);
	bin.end = mid + fabs(numbers.lastObject.floatValue);
	
	return bin;
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
