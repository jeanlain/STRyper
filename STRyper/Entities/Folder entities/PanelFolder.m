//
//  PanelFolder.m
//  STRyper
//
//  Created by Jean Peccoud on 24/11/2022.
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



#import "PanelFolder.h"
#import "Panel.h"
#import "Mmarker.h"
#import "Bin.h"
#import "NSArray+NSArrayAdditions.h"

@implementation PanelFolder

static void *subfoldersChangedContext = &subfoldersChangedContext;
NSNotificationName const PanelFolderSubfoldersDidChangeNotification = @"PanelFolderSubfoldersDidChangeNotification";


/// global variables use during panel import from a text file
NSArray const * _Nonnull channelColorNames;	/// channel color names in the order used through the app
static NSString *fileErrorSuggestion;		/// a generic suggestion in case of error during import.
static NSDictionary *fieldDescription;		/// describe the field of a text file that describes a panel
static NSNumberFormatter *numberFormatter;	/// a number formatter used during panel decoding from a text file

NSString * _Nonnull const PanelMarkersKey = @"markers";
NSString * _Nonnull const PanelSamplesKey = @"samples";


+ (void)initialize {
	if (self == PanelFolder.class) {
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
		/// except for "yellow", which corresponds to channel 2 (black).
		channelColorNames = @[@"blue", @"green", @"black", @"red", @"orange", @"yellow"];
		
		numberFormatter = NSNumberFormatter.new;	/// a formatter we use during import
		numberFormatter.decimalSeparator = @".";
	}
}


- (void)awakeFromFetch {
	[super awakeFromFetch];
	[self addObserver:self forKeyPath:@"subfolders" options:NSKeyValueObservingOptionNew context:subfoldersChangedContext];
}


- (void)awakeFromInsert {
	[super awakeFromInsert];
	[self addObserver:self forKeyPath:@"subfolders" options:NSKeyValueObservingOptionNew context:subfoldersChangedContext];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == subfoldersChangedContext) {
		[NSNotificationCenter.defaultCenter postNotificationName:PanelFolderSubfoldersDidChangeNotification object:self];
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}



- (NSSet *)markers {
	/// We implement this getter because a tableview's content is bound to the `markers` property of the selected item (PanelFolder or Panel)
	return nil;
}



-(NSArray *)panels {
	return [self.subfolders.array filteredArrayUsingPredicate:
			[NSPredicate predicateWithBlock:^BOOL(Folder * subfolder, NSDictionary<NSString *,id> * _Nullable bindings) {
		return subfolder.isPanel;
	}]];
}



- (BOOL) addPanelsFromTextFile:(NSString *)path error:(NSError *__autoreleasing  _Nullable *)error {
	
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
	NSString *panelString = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
	if(readError) {
		if (error != NULL) {
			*error = readError;
		}
		return NO;
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
	
	NSArray *fields = [self.class fieldArrayFromPanelString:panelString];

	int line = 0;			/// the line number is used to show the user which line is problematic in case of failure
	for (NSArray *columns in fields) {
		line++;
		
		/// We identify the entity described in the line
		NSString *type = [columns.firstObject stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet];
		type = type.lowercaseString;
		
		if([type rangeOfString:@"#"].location == 0 || (type.length == 0 && columns.count == 1)) {
			/// we skip comment lines or empty lines
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
					*error = [NSError fileReadErrorWithFileName:path Errors:errors];
				}
				return NO;
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
		NSManagedObject *obj = [self entityForType:type withFields:retainedFields atLine:line ofFile:path error:&parseError];
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
			panel = (Panel *)obj;
			panel.parent = self;
			[panel autoName];
			
		} else if ([obj isKindOfClass: Mmarker.class]) {
			if(!panel) {
				if (!panelParseErrors && !noPanelErrors && !numberOfFieldsErrors && !unknownFieldErrors) {
					noPanelErrors++;
					markerParseErrors++;
					/// We report that a marker is described before the panel only if some errors were not reported before.
					/// We won't complain that a panel has not been described if the user only made a typo in the line describing it.
					/// And we won't report it for each marker
					NSString *reason = [NSString stringWithFormat:@"Line %d: A marker is described before the first panel.", line];
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
																   suggestion:@"The line after the panel description must describe a marker."
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
	
	if(!panel) {
		if(error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"No panel was found in the file."];
			*error = [NSError fileReadErrorWithDescription:reason
														   suggestion:@"Check that the file follows the format specified in the user guide."
															 filePath:path
															   reason:reason];

		}
		return NO;
	}
	
	if(errors.count > 0) {
		if(error != NULL) {
			if(errors.count == 1) {
				*error = errors.firstObject;
			} else {
				*error = [NSError fileReadErrorWithFileName:path Errors:errors];
			}
		}
	}
	return errors.count == 0;
}

/// Returns an array of fields component from a string that should represent a panel.
///
/// The method tries to detect if the format is from genemapper and returns a result that is formatted like STRyper.
+ (NSArray<NSString *> *)fieldArrayFromPanelString:(NSString *)panelString {
	/// We replace Windows newline characters by standard ones, otherwise we may produce additional empty lines.
	NSString *correctedPanelString = [panelString stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	NSArray *lines = [correctedPanelString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:lines.count];
	
	BOOL panelFound = NO;
	BOOL genemapperFormat = NO;
	for(NSString *line in lines) {
		NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
		NSString *firstField = [fields.firstObject.lowercaseString stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet];
		BOOL notJustSpaces = [line stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet].length > 0;
		if(notJustSpaces && [firstField rangeOfString:@"#"].location != 0) {
			/// The line is not a blank or comment line
			if([firstField isEqualToString:@"version"]) {
				if(!panelFound) {
					/// In the genemapper format, the first uncommented line should specify version.
					/// This determination is not much elaborate...
					genemapperFormat = YES;
				}
			}
			if(genemapperFormat) {
				if([firstField isEqualToString:@"panel"]) {
					panelFound = YES;
					if(fields.count > 2) {
						/// Genemapper has three fields for the panel (I don't know what the third field represents), but we only need two ("Panel" and its name)
						fields = [fields objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
					}
				} else if(panelFound) {
					if(fields.count >= 6) {
						/// This should be a field describing a marker. We only need its first 6 fields.
						fields = [fields objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 6)]];
						NSMutableArray *fieldCopy = fields.mutableCopy;
						fieldCopy[4] = @"2";	/// This field seems to be "-" in genemapper, but we use it to denote the ploidy.
						/// We move the channel field from 2nd position to 4th position.
						id channel = fieldCopy[1];
						[fieldCopy removeObjectAtIndex:1];
						[fieldCopy insertObject:channel atIndex:3];
						[fieldCopy insertObject:@"marker" atIndex:0];
						fields = [NSArray arrayWithArray:fieldCopy];
					}
				} else {
					/// If no panel is described yet, this should be a preceding line that describes the version, kit type, etc.
					/// We comment it (we don't remove them to preserve the line numbers).
					fields = @[[@"#" stringByAppendingString:line]];
				}
			}
		}
		[results addObject:fields];
	}
	return results;
}


/// Generate an entity (Panel, Marker or Bin) corresponding to a line containing fields
- (NSManagedObject *)entityForType:(NSString *)type withFields:(NSArray <NSString *>*)fields atLine:(int)line ofFile:(NSString *)path error:(NSError *__autoreleasing *)error {
	
	NSArray *keys =  fieldDescription[type];
	NSString *entityName = keys.firstObject;
	NSManagedObject *obj = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:self.managedObjectContext];
	
	for (int i = 0; i < fields.count; i++) {
		NSString *field = fields[i];
		if(field.length == 0) {
			if (error != NULL) {
				NSString *reason = [NSString stringWithFormat:@"Line %d: column %d is empty.", line, i];
				*error = [NSError fileReadErrorWithDescription:reason
													suggestion:fileErrorSuggestion
													  filePath:path
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
															suggestion:@"This column must contain either 'blue', 'green', 'black, 'yellow', 'red' or 'orange'"
															  filePath:path
																reason:reason];
					}
					
					return obj;
				}
				if(channel == 5) {	/// The yellow color is equivalent to the black color.
					channel = 2;
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


- (nullable NSString *) exportString {
	NSArray *panels = self.panels;
	
	if(panels.count > 0) {
		NSArray *sortedPanels = [panels sortedArrayUsingKey:@"name" ascending:YES];
		NSArray *panelString = [sortedPanels valueForKeyPath:@"@unionOfObjects.exportString"];
		return [panelString componentsJoinedByString:@"\n"];
	}
	return nil;
}


+(BOOL)supportsSecureCoding {
	return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder {
	/// If a Folder Panel is encoded when a sample folder is archived, it means that the samples have at least one panel within a folder.
	/// So we encode our parent folder to preserve the original hierarchy up to the root. We do not encode the subfolders, which may contain irrelevant panels
	[super encodeWithCoder:coder];
	if(self.parent.parent) {
		/// we do not encode the root folder (which has no parent and is invisible to the user)
		[coder encodeObject:self.parent forKey:@"parent"];
	}
}


- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		self.parent = [coder decodeObjectOfClass:PanelFolder.class forKey:@"parent"];
	}
	return self;
}

@end
