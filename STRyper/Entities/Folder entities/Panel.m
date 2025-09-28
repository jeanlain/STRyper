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


- (NSSet *)panels {
	return [NSSet setWithObject:self];
}


- (NSSet *)allPanels {
	return [NSSet setWithObject:self];
}


- (NSString *)exportString {
	NSMutableArray *exportStrings = NSMutableArray.new;
	[exportStrings addObject:[NSString stringWithFormat:@"panel\t%@", self.name]];
	NSArray *sortedMarkers = [self.markers.allObjects sortedArrayUsingKey:@"name" ascending:YES];
	for(Mmarker *marker in sortedMarkers) {
		/// for each marker, we use the "marker" keyword and specify all relevant properties
		[exportStrings addObject:marker.stringRepresentation];
		NSArray *sortedBins = marker.sortedBins;
		NSArray *binStrings = [sortedBins valueForKeyPath:@"@unionOfObjects.stringRepresentation"];
		if(binStrings.count > 0) {
			[exportStrings addObjectsFromArray:binStrings];
		}
	}
	return [[exportStrings componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}


- (nullable NSSet<Bin*> *)updateBinsWithFile:(NSString *)path error:(NSError *__autoreleasing  _Nullable *)error {
	
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
	NSString *binSetString = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return nil;
	}
	
	binSetString = [binSetString stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	
	/// Will contain errors founds, to report as many as possible to the user, so they can correct all without retrying.
	NSMutableArray *errors = NSMutableArray.new;

	NSMutableSet<Bin*> *binsAdded = NSMutableSet.new; /// bins added to markers
	NSMutableArray<NSString*> *markerNames = NSMutableArray.new; /// names of markers found in the file
	BOOL binFound = NO, /// Whether bin description were found for markers of the panel
	panelFound = NO,	/// Whether any panel name was found
	thisPanelFound = NO, /// Whether the name corresponding to this panel was found.
	geneMapperFile = NO; /// Whether the file is a GeneMapper file
	
	NSArray *lines = [binSetString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSMutableArray *fields = [NSMutableArray arrayWithCapacity:lines.count];
	for (NSString *line in lines) {
		/// fields are separated by tabulations.
		[fields addObject:[line componentsSeparatedByString:@"\t"]];
	}
	
	Mmarker *currentMarker; /// The marker for which the current line describes a bin.
	
	int line = 0;			/// to show the user which line is problematic in case of error
	for (NSArray<NSString *> *columns in fields) {
		
		line++;
		NSString *firstField = [columns.firstObject stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet].lowercaseString;
		if([firstField rangeOfString:@"#"].location == 0) {
			continue;
		}
		
		if(firstField.length == 0 && columns.count == 1) {
			/// we skip any empty line
			continue;
		}
		
		if(columns.count < 2) {
			if (error != NULL) {
				NSString *reason = [NSString stringWithFormat:@"Insufficient number of fields at line %d.", line];
				*error = [NSError fileReadErrorWithDescription:reason
													suggestion:@"Check that fields are separated by tabulations."
													  filePath:path
														reason:reason];
			}
			return nil;
		}
		
		
		if([@[@"panel name", @"panel"] containsObject:firstField]) {
			if(!geneMapperFile) {
				geneMapperFile = [firstField isEqualToString:@"panel name"];
			}
			if(thisPanelFound) {
				/// The target panel has already been found, this should be the description of the next panel.
				/// There is no need to read lines further.
				break;
			}
			panelFound = YES;
			NSString *panelName = columns[1];
			thisPanelFound = [panelName isEqualToString:self.name];
			continue;
		}
		
		if((geneMapperFile && [firstField isEqualToString:@"marker name"]) || [firstField isEqualToString:@"marker"]) {
			if(!panelFound) {
				if (error != NULL) {
					NSString *reason = [NSString stringWithFormat:@"Line %d: a marker name is specified before any panel.", line];
					*error = [NSError fileReadErrorWithDescription:reason
														suggestion:@"Ensure that a line starts with 'panel' or 'Panel Name' early in the file."
														  filePath:path
															reason:reason];
				}
				return nil;
			}
			currentMarker = nil;
			if(!thisPanelFound) {
				/// The marker is not in the panel we want.
				continue;
			}
			
			NSString *markerName = columns[1];
			if([markerNames containsObject:markerName]) {
				if (error != NULL) {
					NSString *reason = [NSString stringWithFormat:@"Line %d: marker %@ is listed twice in the panel.", line, markerName];
					*error = [NSError fileReadErrorWithDescription:reason
														suggestion:@"Each marker must appear only once per panel."
														  filePath:path
															reason:reason];
				}
				return nil;
			}
			for(Mmarker *marker in self.markers) {
				if([marker.name isEqualToString:markerName]) {
					currentMarker = marker;
					marker.bins = nil;
					[markerNames addObject:markerName];
					break;
				}
			}
		} else {
			if(currentMarker) {
				Bin *bin = nil;
				NSError *binError;
				if(!geneMapperFile) {
					if(![firstField isEqualToString:@"bin"]) {
						if (error != NULL) {
							NSString *reason = [NSString stringWithFormat:@"Line %d should start with 'bin', but %@ was found.", line, firstField];
							*error = [NSError fileReadErrorWithDescription:reason
																suggestion:@"Ensure that all lines between marker descriptions describe bins."
																  filePath:path
																	reason:reason];
						}
						return nil;
					}
					
					binFound = YES;
					if(columns.count < 4) {
						if (error != NULL) {
							NSString *reason = [NSString stringWithFormat:@"Line %d: was expecting 4 columns for bin description but found %ld.", line, columns.count];
							*error = [NSError fileReadErrorWithDescription:reason
																suggestion:@"Check the file. Encoding must be ASCII or UTF-8 and fields separated by tabs"
																  filePath:path
																	reason:reason];
						}
						return nil;
					}
					NSArray *retainedFields = [columns objectsAtIndexes: [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)]];
					bin = [(PanelFolder *)self.parent entityForType:firstField withFields:retainedFields atLine:line ofFile:path error:&binError];
				} else {
					bin = [self binWithGenemapperFields:columns atLine:line ofFile:path error:&binError];
				}
				
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
						[binsAdded addObject:bin];
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
	} else if(!panelFound) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"No line specifying a panel was found in the file."];
			*error = [NSError fileReadErrorWithDescription:reason
												suggestion:@"Verify that a line starts with 'panel' or 'Panel Name' (GeneMapper format)."
												  filePath:path
													reason:reason];
		}
	} else if(!thisPanelFound) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"No panel named '%@' was found in the file.", self.name];
			*error = [NSError fileReadErrorWithDescription:reason
												suggestion:@"Verify that the panel name appears in the 2nd column after 'panel' or 'Panel Name' (GeneMapper format)."
												  filePath:path
													reason:reason];
		}
	} else if(markerNames.count == 0) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"None of the markers of panel '%@' was found in the file.", self.name];
			*error = [NSError fileReadErrorWithDescription:reason
												suggestion:@"Verify that a line starts with 'Marker' or 'Marker Name' (GeneMapper format)."
												  filePath:path
													reason:reason];
		}
	} else if(!binFound && error != NULL) {
		NSString *reason = [NSString stringWithFormat:@"No bin description was found."];
		*error = [NSError fileReadErrorWithDescription:reason
											suggestion:@"Check for lines describing bins after the line describing a marker."
											  filePath:path
												reason:reason];
	}
	return binsAdded.copy;
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
	return [self.markers.allObjects filteredArrayUsingBlock:^BOOL(Mmarker*  _Nonnull marker, NSUInteger idx) {
		return marker.channel == channel;
	}];
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
