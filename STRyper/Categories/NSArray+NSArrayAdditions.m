//
//  NSArray+NSArrayAdditions.m
//  STRyper
//
//  Created by Jean Peccoud on 27/10/2023.
//
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


#import "NSArray+NSArrayAdditions.h"

@implementation NSArray (NSArrayAdditions)



- (NSArray *)sortedArrayUsingKey:(NSString *)key ascending:(BOOL)ascending {
	NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:key ascending:ascending];
	return [self sortedArrayUsingDescriptors:@[desc]];
	
}


-(BOOL) isIdenticalTo:(NSArray *) array {
	NSInteger count = self.count;
	if(array.count != self.count) {
		return NO;
	}
	for(int i = 0; i < count; i++) {
		if([self objectAtIndex:i] != array[i]) {
			return NO;
		}
	}
	return YES;
}


-(NSArray *) arrayByRemovingObjectsIdenticalInArray:(NSArray *)array {
	return [self filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
		return [array indexOfObjectIdenticalTo:evaluatedObject] == NSNotFound;
	}]];
}


-(NSArray *) arrayByRemovingObjectsInArray:(NSArray *)array {
	return [self filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
		return ![array containsObject:evaluatedObject];
	}]];
}


@end
