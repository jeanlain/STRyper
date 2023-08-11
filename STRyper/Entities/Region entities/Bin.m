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
		if (error != NULL) {
			*error = [NSError managedObjectValidationErrorWithDescription:@"The bin has no name."
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
	}
	[self managedObjectOriginal_setStart:start];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName:@"Edit Bin"];
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
	}
	[self managedObjectOriginal_setEnd:end];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName:@"Edit Bin"];
	}
}


- (void)setName:(NSString *)name {
	if(name != self.name) {
		for(Genotype *genotype in self.marker.genotypes) {
			GenotypeStatus status = genotype.status;
			if(status != genotypeStatusNotCalled) {
				genotype.status = genotypeStatusMarkerChanged;
			}
		}
	}
	[self managedObjectOriginal_setName:name];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName:@"Rename Bin"];
	}
}


- (void)setMarker:(nullable Mmarker *)marker {
	/// a bin without a marker must be deleted
	BOOL shouldDelete = self.marker != nil && marker == nil && !self.deleted;
	[self managedObjectOriginal_setMarker:marker];
	if(shouldDelete) {
		[self.managedObjectContext deleteObject:self];
	}
}


- (BOOL)validateCoordinate:(float) coordinate isStart:(bool)isStart error:(NSError **)error {
	NSString *coord = isStart? @"start" : @"end";
	Mmarker *marker = self.marker;
	if(self.marker && (coordinate < marker.start || coordinate > marker.end)) {
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat: @"Bin '%@': %@ position %g is out of marker '%@' range (%g-%g bp).", self.name, coord, coordinate, marker.name, marker.start, marker.end];
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:description];
		}
		return NO;
	}
		
	float start = 0, end = 0;
	if(isStart) {
		start = coordinate;
		end = self.end;
	} else {
		start = self.start;
		end = coordinate;

	}
	
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
	return [NSString stringWithFormat:@"bin\t%@\t%g\t%g\n", self.name, self.start, self.end];
}


@end
