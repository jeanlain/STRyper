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



@implementation Region

@dynamic name, start, end;
@synthesize editState = _editState;


- (void)setName:(NSString *)name {
	[self managedObjectOriginal_setName:name];
	if(!self.deleted) {
		[self.managedObjectContext.undoManager setActionName: [@"Rename " stringByAppendingString: self.entity.name]];
	}
}


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
	float min = 0, max = 0, margin = 0, leftLimit = 0, rightLimit = 0;
	NSArray *siblings;
	if(self.class == Mmarker.class) {
		min = 0;
		max = MAX_TRACE_LENGTH;
		margin = 1;
		Mmarker *marker = (Mmarker *)self;
		siblings = [Panel sortByStart: [marker.panel markersForChannel:marker.channel]];
	} else {
		Mmarker *marker = ((Bin *)self).marker;
		min = marker.start;           						/// if we are a bin, the min and max position are defined by the range of our marker
		max = marker.end;
		margin = 0.05;
		siblings = [Panel sortByStart:self.siblings];
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
			NSArray *sortedBins = [Panel sortByStart:bins.allObjects];
			if(edge == leftEdge) {
				rightLimit = ((Region *)sortedBins.firstObject).start;
			} else {
				leftLimit = ((Region *)sortedBins.lastObject).end;
			}
		}
	}
	return MakeBaseRange(leftLimit, rightLimit - leftLimit);
}

- (void)autoName {
	/// overridden
}

- (NSArray *)siblings {
	/// overridden
	return NSArray.new;
}



- (BOOL)validateStart:(id *)valueRef error:(NSError **)error {
	float start = [*valueRef floatValue];
	return [self validateCoordinate:start isStart:YES error:error];
}


- (BOOL)validateEnd:(id *)valueRef error:(NSError **)error {
	float end = [*valueRef floatValue];
	return [self validateCoordinate:end isStart:NO error:error];
}


- (BOOL)validateCoordinate:(float) value isStart:(bool)isStart error:(NSError **)error {
	return YES; /// overridden
}

@end
