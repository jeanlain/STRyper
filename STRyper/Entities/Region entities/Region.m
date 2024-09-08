//
//  Region.m
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



#import "Region.h"
#import "Mmarker.h"
#import "Bin.h"
#import "Panel.h"
#import "Chromatogram.h"
#import "NSArray+NSArrayAdditions.h"

CodingObjectKey regionStartKey = @"start",
regionEndKey = @"end",
regionNameKey = @"name",
regionEditStateKey = @"editState";

@implementation Region {
	BOOL globalValidation; /// Tells whether the object validates all changed attributes.
						   /// We use to determine if we correct a invalid value or not.
}

@dynamic name, start, end;
@synthesize editState = _editState;



- (BOOL) overlapsWith:(Region *)region {
	return [self overlapsWithBaseRange:MakeBaseRange(region.start, region.end - region.start)];
}


- (BOOL) overlapsWithBaseRange:(BaseRange)range {
	float start = range.start;
	float end = range.start + range.len;
	return self.start <= end && self.end >= start ;
}


-(BaseRange)allowedRangeForEdge:(RegionEdge)edge {
	/// min and max allowed positions for the edge, the margin we have for collision with another edge
	float min = 0, max = 0, margin = self.minimumWidth/2, leftLimit = 0, rightLimit = 0;
	NSArray *siblings;
	if(self.class == Mmarker.class) {
		min = 0;
		max = MAX_TRACE_LENGTH;
		Mmarker *marker = (Mmarker *)self;
		siblings = [[marker.panel markersForChannel:marker.channel] sortedArrayUsingKey:@"start" ascending:YES];
	} else {
		Mmarker *marker = ((Bin *)self).marker;
		min = marker.start;           						/// if we are a bin, the min and max position are defined by the range of our marker
		max = marker.end;
		siblings = [self.siblings sortedArrayUsingKey:@"start" ascending:YES];
	}
	
	for(Region *region in siblings) {
		if(region.end < self.start) {
			min = region.end;
		} else if(region.start > self.end) {
			max = region.start;
			break;
		}
	}
	
	if(edge == leftEdge) {
		/// we also consider that our start must be lower than our end (with a margin)
		leftLimit = min + margin;
		rightLimit = self.end - margin*2;
	} else if(edge == rightEdge) {
		leftLimit = self.start + margin*2;
		rightLimit = max - margin;
	} else {
		leftLimit = min + margin;
		rightLimit = max - margin;
	}
								
	if(self.class == Mmarker.class) {       			/// if we are a marker, our range must also consider all our bins
		NSSet *bins = ((Mmarker *)self).bins;
		if(bins.count > 0)  {
			NSArray <Region *>*sortedBins = [bins.allObjects sortedArrayUsingKey:@"start" ascending:YES];
			if(edge == leftEdge) {
				rightLimit = sortedBins.firstObject.start;
			} else {
				leftLimit = sortedBins.lastObject.end;
			}
		}
	}
	return MakeBaseRange(leftLimit, rightLimit - leftLimit);
}


- (void)autoName {
	/// overridden
}


- (void)setName:(NSString *)name {
	if(![name isEqualToString:self.name]) {
		[self managedObjectOriginal_setName:name];
	}
}

- (NSArray *)siblings {
	/// overridden
	return NSArray.new;
}


- (float)minimumWidth {
	return 0;
}


- (BOOL)validateForUpdate:(NSError *__autoreleasing  _Nullable *)error {
	globalValidation = YES;
	BOOL response = [super validateForUpdate:error];
	globalValidation = NO;
	return response;
}


- (BOOL)validateForInsert:(NSError *__autoreleasing  _Nullable *)error {
	globalValidation = YES;
	BOOL response = [super validateForInsert:error];
	globalValidation = NO;
	return response;
}


- (BOOL)validateStart:(id *)valueRef error:(NSError **)error {
	return [self validateCoordinate:valueRef isStart:YES error:error];
}


- (BOOL)validateEnd:(id *)valueRef error:(NSError **)error {
	return [self validateCoordinate:valueRef isStart:NO error:error];
}


- (BOOL)validateCoordinate:(id _Nullable *)valueRef isStart:(BOOL)isStart error:(NSError * _Nullable*)error {
	NSNumber *coord = *valueRef;
	if(coord == nil) {
		/// A coordinate is required.
		if(!globalValidation) {
			/// If none is provided and the coordinate is validated separately from other attributes, we try to use the previous one.
			NSNumber *previousCoord = isStart? @(self.start) : @(self.end);
			if([self validateCoordinate:&previousCoord isStart:isStart error:nil]) {
				*valueRef = previousCoord;
				return YES;
			}
		}
		
		if (error != NULL) {
			NSString *string = isStart? @"start" : @"end";
			NSString *description = [NSString stringWithFormat: @"A coordinate for the %@ %@ must be specified.", self.entity.name, string];
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:@""];
		}
		return NO;
	}
	
	/// Then we check of the coordinate is within the allowed range.
	float coordinate = coord.floatValue;	/// Possible corrected value.
	
	BaseRange allowedRange = isStart? [self allowedRangeForEdge:leftEdge] : [self allowedRangeForEdge:rightEdge];
	float rangeStart = allowedRange.start;
	float rangeEnd = rangeStart + allowedRange.len;
	float newCoordinate = coordinate;
	if(coordinate < rangeStart) {
		newCoordinate = rangeStart;
	} else if(coordinate > rangeEnd) {
		newCoordinate = rangeEnd;
	}
	
	if(newCoordinate != coordinate) {
		if(!globalValidation) {
			/// We may replace the coordinate if the object is not validating attributes globally.
			/// We check that the corrected coordinate still maintains the region minimum width.
			float start = isStart? newCoordinate : self.start;
			float end = isStart? self.end : newCoordinate;
			
			if(end - start < self.minimumWidth) {
				if (error != NULL) {
					NSString *description = [NSString stringWithFormat: @"There is no room for the %@.", self.entity.name]; /// Subclasses can provided a more detailed error.
					*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:@""];
				}
				return NO;
			}
			*valueRef = @(newCoordinate);
			return YES;
		}
		if (error != NULL) {
			NSString *string = isStart? @"start" : @"end";
			NSString *description = [NSString stringWithFormat: @"Value %0.01f for the %@ %@ is invalid.", coordinate, self.entity.name, string];  /// Subclasses can provided a more detailed error.
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:@""];
		}
		return NO;
	}
	
	
	return YES;
}

@end
