//
//  Bin.m
//  STRyper
//
//  Created by Jean Peccoud on 07/03/2022.
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



#import "Bin.h"
#import "Mmarker.h"
#import "Genotype.h"
#import "Chromatogram.h"

@implementation Bin

@dynamic marker;

-(instancetype) initWithStart:(float) start end:(float) end marker:(Mmarker *)marker {
	if(!marker.managedObjectContext) {
		NSLog(@"the provided marker has no managed object context!");
		return nil;
	}
	if(start < 0 || end <= 0 || start >= MAX_TRACE_LENGTH || end > MAX_TRACE_LENGTH || start >= end) {
		NSLog(@"The star/end coordinates of the bin are invalid.");
		return nil;
	}
	
	self = [super initWithContext:marker.managedObjectContext];
	if(self) {
		self.start = start;
		self.end = end;
		self.marker = marker;
		[self autoName];
	}
	return self;
}


- (NSArray *)siblings {
	if(self.marker) {
		return self.marker.bins.allObjects;
	}
	return NSArray.new;
}


- (void)autoName {
	/// the name of a bin is derived from the size at its midpoint
    float mid = (self.start + self.end) / 2;
    int round = mid;
    round = (mid - round <= 0.5)? round: round+1;
    NSString *name;
	/// if the name already exists, we add a suffix. Note that we don't forbid duplicate bin names like we do for marker names.
	/// The user can set whatever name he wants manually
	int i = 0;
	NSString *suffix = @"";
	BOOL ok = NO;
    while(!ok) {
		if(i > 0) {
			suffix = [NSString stringWithFormat:@".%d",i];
		}
        name = [NSString stringWithFormat:@"%d%@", round, suffix];
		if(self.marker.bins.count == 0) {
			ok = YES;
		}
        for (Bin *bin in self.marker.bins) {
            if([name isEqualToString:bin.name] && bin != self) {
                ok = NO;
                break;
			} else {
				ok = YES;
			}
        }
        i++;
    }
    self.name = name;
}


- (BOOL)validateName:(id *) value error:(NSError **)error {
	/// the bin must have a name
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
			*error = [NSError managedObjectValidationErrorWithDescription:@"The bin must have a name."
															   suggestion:@""
																   object:self
																   reason:@"The bin has no name."];

		} 
		return NO;
	}
	
	return YES;
}



- (void)setStart:(float)start {
	/// Like for markers, when a bin is edited, we mark the status of genotypes accordingly
	if(start != self.start) {
		for(Genotype *genotype in self.marker.genotypes) {
			GenotypeStatus status = genotype.status;
			if(status != genotypeStatusNotCalled) {
				genotype.status = genotypeStatusMarkerChanged;
			}
		}
		[self managedObjectOriginal_setStart:start];
	}
}


- (void)setEnd:(float)end {
	if(end != self.end) {
		for(Genotype *genotype in self.marker.genotypes) {
			GenotypeStatus status = genotype.status;
			if(status != genotypeStatusNotCalled) {
				genotype.status = genotypeStatusMarkerChanged;
			}
		}
		[self managedObjectOriginal_setEnd:end];
	}
}


- (void)setName:(NSString *)name {
	if(![name isEqualToString:self.name]) {
		[self managedObjectOriginal_setName:name];
		for(Genotype *genotype in self.marker.genotypes) {
			GenotypeStatus status = genotype.status;
			if(status != genotypeStatusNotCalled) {
				genotype.status = genotypeStatusMarkerChanged;
			}
		}
	}
}


- (void)setMarker:(nullable Mmarker *)marker {
	/// A bin without a marker must be deleted
	BOOL shouldDelete = self.marker != nil && marker == nil && !self.deleted;
	[self managedObjectOriginal_setMarker:marker];
	if(shouldDelete) {
		[self.managedObjectContext deleteObject:self];
	}
}


- (float)minimumWidth {
	return 0.1;
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
	Mmarker *marker = self.marker;
	if(self.marker && (coordinate < marker.start || coordinate > marker.end)) {
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat: @"Bin '%@': %@ position %g is out of marker '%@' range (%g-%g bp).", self.name, coord, coordinate, marker.name, marker.start, marker.end];
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:description];
		}
		return NO;
	}

	float start = isStart? coordinate : self.start;
	float end = isStart? self.end : coordinate;
	if(end - start < 0.1) {
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat: @"Bin '%@' range is too short.", self.name];
			*error = [NSError managedObjectValidationErrorWithDescription: description
															   suggestion:@"A bin range must be at least 0.1 base pair."
																   object:self
																   reason: description];
		}
		return NO;
	}
	
	for(Bin *bin in marker.bins) {
		if(bin != self && [bin overlapsWithBaseRange:MakeBaseRange(start, end - start)]) {
			if (error != NULL) {
				NSString *description = [NSString stringWithFormat: @"Bin '%@' overlaps bin '%@'.", self.name, bin.name];
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

- (NSString *)stringRepresentation {
	return [NSString stringWithFormat:@"bin\t%@\t%.2f\t%.2f", self.name, self.start, self.end];
}


@end
