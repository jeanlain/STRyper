//
//  SizeStandardSize.m
//  STRyper
//
//  Created by Jean Peccoud on 21/12/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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



#import "SizeStandardSize.h"
#import "SizeStandard.h"


@interface SizeStandardSize (DynamicAccessors)

-(void)managedObjectOriginal_setSize:(int16_t)size;
-(void)managedObjectOriginal_setSizeStandard:(SizeStandard *)sizeStandard;

@end


@implementation SizeStandardSize

@dynamic size;
@dynamic sizeStandard;


- (void)setSize:(int16_t)size {
	if(size != self.size) {
		[self managedObjectOriginal_setSize:size];
	}
}


- (void)autoSize {
	int16_t size = self.size;
	if(size < 10) {
		size = 10;
	}
	NSMutableSet *siblings = [NSMutableSet setWithSet: self.sizeStandard.sizes];
	[siblings removeObject:self];
	
	NSArray *otherSizes = [siblings.allObjects valueForKeyPath:@"@unionOfObjects.size"];
	
	int16_t increment = size > 1500? -1 : 1;
	while([otherSizes containsObject:@(size)] || size > 1500) {
		size += increment;
	}
	
	[self managedObjectOriginal_setSize:size];
}


- (BOOL)validateSize:(id  _Nullable __autoreleasing *) value error:(NSError *__autoreleasing  _Nullable *)error {
	NSNumber *sizeNumber = *value;
	if(!*value) {
		NSNumber *previousSize = @(self.size);
		if([self validateSize:&previousSize error:nil]) {
			*value = previousSize;
			return YES;
		}
		
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat:@"The size must be specified."];
			NSString *reason = [NSString stringWithFormat:@"A size standard fragment must have a size."];
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:reason];
		}
		return NO;
	}
	
	int16_t size = sizeNumber.shortValue;
	if(size < 10) {
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat:@"The size is too short."];
			NSString *reason = [NSString stringWithFormat:@"A size must be at least 10 bp."];
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:reason object:self reason:reason];
		}
		return NO;
	}

	if(size > 1500) {
		if (error != NULL) {
			NSString *description = [NSString stringWithFormat:@"The size is too large."];
			NSString *reason = [NSString stringWithFormat:@"A size cannot exceed 1500 bp."];
			*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:reason object:self reason:reason];
		}
		return NO;
	}
	
	/// we avoid duplicate sizes

	NSSet *siblings = self.sizeStandard.sizes;
	if(siblings.count > 0) {
		for (SizeStandardSize *fragment in siblings) {
			if(fragment.size == size && fragment != self) {
				if (error != NULL) {
					NSString *description = [NSString stringWithFormat:@"Size %d is already in use in the size standard.", size];
					NSString *reason = [NSString stringWithFormat:@"Duplicate size ('%d').", size];
					*error = [NSError managedObjectValidationErrorWithDescription:description suggestion:@"" object:self reason:reason];
				}

				return NO;
			}
		}
	}
   
	return YES;
}


- (void)setSizeStandard:(SizeStandard *)sizeStandard {
	/// a size without a size standard must be deleted
	BOOL shouldDelete = self.sizeStandard != nil && sizeStandard == nil && !self.deleted;
	[self managedObjectOriginal_setSizeStandard:sizeStandard];
	if(shouldDelete) {
		[self.managedObjectContext deleteObject:self];
	}
}


@end
