//
//  Mmarker.m
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



#import "Mmarker.h"
#import "Panel.h"
#import "Bin.h"
#import "Allele.h"
#import "Genotype.h"
#import "Chromatogram.h"

@interface Mmarker ()

@property (nonatomic, readonly) NSImage *channelImage;
@property (nonatomic, readonly) NSString *channelName;

@end


@implementation Mmarker

@dynamic ploidy, channel, motiveLength, bins, panel, genotypes;
@synthesize channelImage, channelName;

NSString * _Nonnull const MarkerBinsKey = @"bins";
NSString * _Nonnull const MarkerPanelKey = @"panel";
NSPasteboardType _Nonnull const MarkerPasteboardType = @"org.jpeccoud.stryper.markerPasteboardType";
static void * const binsChangedContext = (void*)&binsChangedContext;



- (nullable instancetype)initWithStart:(float)start
								   end:(float)end
							   channel:(ChannelNumber)channel
								ploidy:(Ploidy)ploidy
								 panel:(Panel *)panel {
	if(!panel.managedObjectContext) {
		return nil;
	}
	self = [super initWithContext:panel.managedObjectContext];
	if(self) {
		self.start = start;
		self.end = end;
		[self managedObjectOriginal_setChannel:channel];
		[self managedObjectOriginal_setPloidy:ploidy];
		[self managedObjectOriginal_setPanel:panel];
		[self autoName];
	}
	return self;
}


/// convenience method that returns the color name for our channel
/// This can be used in the UI.
- (NSString *)channelName {
	if(self.channel >= 0 && self.channel < channelColorNames.count) {
		return [channelColorNames objectAtIndex:self.channel];
	}
	return @"invalid channel";
}


- (NSArray<Bin *> *)sortedBins {
	return [self.bins.allObjects sortedArrayUsingComparator:^NSComparisonResult(Bin *bin1, Bin *bin2) {
		if(bin1.start < bin2.start) {
			return NSOrderedAscending;
		}
		return NSOrderedDescending;
	}];
}


- (NSArray *)siblings {
	if(self.panel) {
		return self.panel.markers.allObjects;
	}
	return NSArray.new;
}


- (void)setStart:(float)start {
	/// when these attribute change, we make the user know that the marker has been modified for any genotype generated for this marker
	if(self.start != start) {
		for(Genotype *genotype in self.genotypes) {
			GenotypeStatus status = genotype.status;
			if(status != genotypeStatusNotCalled) {
				genotype.status = genotypeStatusMarkerChanged;
			}
		}
		[self managedObjectOriginal_setStart:start];
	}
}


- (void)setEnd:(float)end {		/// see -setStart:
	if(self.end != end) {
		for(Genotype *genotype in self.genotypes) {
			GenotypeStatus status = genotype.status;
			if(status != genotypeStatusNotCalled) {
				genotype.status = genotypeStatusMarkerChanged;
			}
		}
		[self managedObjectOriginal_setEnd:end];
	}
}



- (void)setChannel:(int16_t)channel {
	[self managedObjectOriginal_setChannel:channel];
}


- (BOOL)validateName:(id _Nullable __autoreleasing *) value error:(NSError * _Nullable __autoreleasing *)error {
	/// We avoid duplicate marker names in the panel
	NSString *name = *value;
	if(name.length == 0) {
		NSString *previousName = self.name;
		if(previousName.length > 0) {
			if([self validateName:&previousName error:nil]) {
				*value = previousName;
				return YES;
			}
		}
		if (error != NULL) {
			*error = [NSError managedObjectValidationErrorWithDescription:@"The marker must have a name."
															   suggestion:@""
																   object:self
																   reason:@"The marker has no name."];

		}
		return NO;
	}

	for (Mmarker *marker in self.panel.markers) {
		if(marker != self && [name isEqualToString:marker.name]) {
			
			if (error != NULL) {
				NSString *description = [NSString stringWithFormat:@"A marker with the same name ('%@') is already present in the panel.", self.name];
				*error = [NSError managedObjectValidationErrorWithDescription:description
																   suggestion:@"Please, use another name."
																	   object:self reason:description];
			}
			return NO;
		}
	}
	return YES;
}

- (float)minimumWidth {
	return 2.0;
}

- (BOOL)validateCoordinate:(id *) valueRef isStart:(BOOL)isStart error:(NSError * _Nullable *)error {

	if([super validateCoordinate:valueRef isStart:isStart error:error]) {
		return YES;
	}
	if(*valueRef == nil) {
		/// When the value was not specified, the error is explicit enough.
		return NO;
	}
	
	float coordinate = [*valueRef floatValue];
	
	/// If we're here, we couldn't find a valid coordinate despite corrections.
	/// So we try to specify the error (which may not be fixable if there is no room).
	NSString *coord = isStart? @"start" : @"end";

	if(coordinate < 0 | coordinate > MAX_TRACE_LENGTH) {
		if(error != NULL) {
			NSString *reason =  [NSString stringWithFormat: @"Marker '%@' %@ coordinate of %g is out of allowed range (0-%d).", self.name, coord, coordinate, MAX_TRACE_LENGTH];
			NSString *suggestion = [NSString stringWithFormat: @"Range must be between 0 and %d base pairs.", MAX_TRACE_LENGTH];
			*error = [NSError managedObjectValidationErrorWithDescription:reason
															   suggestion:suggestion
																   object:self reason:reason];
		}
		return NO;
	}
		
	float start = isStart? coordinate : self.start;
	float end = isStart? self.end : coordinate;
	if(end - start < 2.0) {
		if (error != NULL) {
			NSString *reason = [NSString stringWithFormat:@"Marker '%@' range of %g bp is too short (min: 2bp).", self.name, end-start];
			*error = [NSError managedObjectValidationErrorWithDescription: reason
															   suggestion:@"Range must be at least 2 base pairs."
																   object:self
																   reason: reason];
		}
		return NO;
	}
	
	
	for(Mmarker *marker in [self.panel markersForChannel:self.channel]) {
		if(marker != self && [marker overlapsWithBaseRange:MakeBaseRange(start, end - start)]) {
			if (error != NULL) {
				NSString *description = [NSString stringWithFormat:@"Marker '%@' overlaps with marker '%@'.", self.name, marker.name];
				*error = [NSError managedObjectValidationErrorWithDescription:description
																   suggestion:@"You may change one of the marker range or color."
																	   object:self
																	   reason:description];
			}
			return NO;
		}
	}
	
	for (Bin *bin in self.bins) {
		if(bin.start < start || bin.end > end) {
			if (error != NULL) {
				NSString *description = [NSString stringWithFormat: @"Range of marker '%@' excludes bin '%@'.", self.name, bin.name];
				*error = [NSError managedObjectValidationErrorWithDescription: description
																   suggestion:@""
																	   object:self
																	   reason: description];
			}
			return NO;
		}
	}
	
	return YES;
}


- (BOOL)validatePanel:(id _Nullable __autoreleasing *)valueRef error:(NSError * _Nullable __autoreleasing *)error {
	Panel *panel = *valueRef;
	for(Mmarker *marker in panel.markers) {
		if(marker == self) continue;
		if([marker.name isEqualToString:self.name]) {
			if (error != NULL) {
				NSString *description = [NSString stringWithFormat:@"A marker with the same name ('%@') is already present in the panel.", self.name];
				*error = [NSError managedObjectValidationErrorWithDescription:description
																   suggestion:@"Please, use another name."
																	   object:self reason:description];

			}
			return NO;
		}
		if(self.channel == marker.channel) {
			if([self overlapsWith:marker]) {
				
				if (error != NULL) {
					NSString *description = [NSString stringWithFormat:@"Marker '%@' overlaps with marker '%@'.", self.name, marker.name];
					*error = [NSError managedObjectValidationErrorWithDescription:description
																	   suggestion:@"You may change one of the marker range or color."
																		   object:self
																		   reason:description];
				}
				return NO;
			}
		}
	}
	return YES;
}


- (BOOL)validatePloidy:(id _Nullable __autoreleasing *)valueRef error:(NSError * _Nullable __autoreleasing *)error {
	NSNumber *num = *valueRef;
	Ploidy ploidy = num.shortValue;
	
	if(ploidy < haploid) {
		*valueRef = @(haploid);
	} else if(ploidy > diploid) {
		*valueRef = @(diploid);
	}
	
	return YES;
}



- (BOOL)validateChannel:(id _Nullable __autoreleasing *)valueRef error:(NSError * _Nullable __autoreleasing *)error {
	NSNumber *num = *valueRef;
	ChannelNumber channel = num.shortValue;
	
	if(channel < 0) {
		*valueRef = @(0);
	} else if(channel > 3) {
		*valueRef = @(3);
	}
	
	return YES;
}


- (BOOL)validateMotiveLength:(id _Nullable __autoreleasing *)valueRef error:(NSError * _Nullable __autoreleasing *)error {
	NSNumber *num = *valueRef;
	int motiveLength = num.intValue;
	
	if(motiveLength < 2) {
		*valueRef = @(2);
	} else if(motiveLength > 7) {
		*valueRef = @(7);
	}
	
	return YES;
}



- (void)autoName {
	if(self.panel) {
		self.name = [self.panel proposedMarkerName];
	} else {
		self.name = @"marker 1";
	}
}


- (void)createGenotypesWithAlleleName:(NSString *)alleleName {
	for(Chromatogram *sample in self.panel.samples) {
		Genotype *newGenotype = [[Genotype alloc] initWithMarker:self sample:sample];
		for(Allele *allele in newGenotype.alleles) {
			[allele managedObjectOriginal_setName:alleleName];
		}
	}
}

#pragma mark - copying and archiving

- (BOOL)isEquivalentTo:(__kindof NSManagedObject *)obj {
	if(![super isEquivalentTo:obj]) {
		return NO;
	}
	Mmarker *marker = obj;
	if(marker.bins.count != self.bins.count) {
		return NO;
	}
	if(self.bins.count == 0 && marker.bins.count == 0) {
		return YES;
	}
	NSArray *bins = [self.bins sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"start" ascending:YES]]] ;
	NSArray *objBins = [marker.bins sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"start" ascending:YES]]] ;
	for (int i = 0; i < bins.count; i++) {
		if(![bins[i] isEquivalentTo:objBins[i]]) {
			return NO;
		}
	}
	return YES;
}


+(BOOL)supportsSecureCoding {
	return YES;
}


- (void)encodeWithCoder:(NSCoder *)coder {
	[super encodeWithCoder:coder];
	[coder encodeObject:self.bins forKey:MarkerBinsKey];
	/// we don't encode our panel relationship. This relationship is encoded in the opposite direction by the panel
	/// we don't encode the genotype either, as many won't relate to the folder being archived
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		self.bins = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSSet.class, Bin.class, nil]  forKey:MarkerBinsKey];
	}
	return self;
}


- (NSString *)stringRepresentation {
	return [NSString stringWithFormat:@"marker\t%@\t%.2f\t%.2f\t%@\t%d\t%d", self.name, self.start, self.end, self.channelName, self.ploidy, self.motiveLength];
}


- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	/// the string representation of the marker is copied as tabular text, though we don't use it within the app.
	return @[NSPasteboardTypeTabularText, MarkerPasteboardType];
}


- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard {
	return 0;
}


- (id)pasteboardPropertyListForType:(NSPasteboardType)type {
	if ([type isEqualToString:NSPasteboardTypeTabularText]) {
		/// this type of pasteboard doesn't seem to be used in most application...
		return self.stringRepresentation;
	} else if ([type isEqualToString:MarkerPasteboardType]) {
		/// the marker is copied as an archive
		NSError *error;
		NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:YES error:&error];
		
		if(error) {
			NSLog(@"error: %@", error);
		} else {
			return archive;
		}
	}
	return nil;
}

@end
