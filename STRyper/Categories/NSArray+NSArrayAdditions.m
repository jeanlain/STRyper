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


-(BOOL) isEquivalentTo:(NSArray *) array {
	NSInteger count = self.count;
	if(array.count != count) {
		return NO;
	}
	for(int i = 0; i < count; i++) {
		if(self[i] != array[i]) {
			return NO;
		}
	}
	return YES;
}


- (BOOL)containsSameObjectsAs:(NSArray *)array {
	if(array.count != self.count) {
		return NO;
	}
	NSMapTable *identityMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:0];
	for (id obj in array) {
		[identityMap setObject:@YES forKey:obj];
	}
	
	for (id obj in self) {
		if (![identityMap objectForKey:obj]) {
			return NO;
		}
	}
	return YES;
}


- (BOOL)sharesObjectsWithArray:(NSArray *)array {
	if(self.count == 0 || array.count == 0) {
		return NO;
	}
	NSMapTable *identityMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:0];
	for (id obj in array) {
		[identityMap setObject:@YES forKey:obj];
	}
	
	for (id obj in self) {
		if ([identityMap objectForKey:obj]) {
			return YES;
		}
	}
	return NO;
}


-(NSArray *)intersectionWithArray:(NSArray *)array {
	if(!array) {
		return NSArray.new;
	}
	return [self filteredArrayUsingBlock:^BOOL(id  _Nonnull obj, NSUInteger idx) {
		return [array indexOfObjectIdenticalTo:obj] != NSNotFound;
	}];
}


- (BOOL)containsAllObjectsOf:(NSArray *)array {
	for(id object in array) {
		if([self indexOfObjectIdenticalTo:object] == NSNotFound) {
			return NO;
		}
	}
	return YES;
}


- (NSArray *)arrayByRemovingObjectsIdenticalInArray:(NSArray *)array {
	NSMapTable *identityMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:0];
	for (id obj in array) {
		[identityMap setObject:@YES forKey:obj];
	}

	NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
	for (id obj in self) {
		if (![identityMap objectForKey:obj]) {
			[result addObject:obj];
		}
	}
	return result.copy;
}



- (NSArray *)arrayByRemovingObjectsInArray:(NSArray *)array {
	NSSet *removalSet = [NSSet setWithArray:array];
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
	for (id obj in self) {
		if (![removalSet containsObject:obj]) {
			[result addObject:obj];
		}
	}
	return result.copy;
}



- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(id obj, NSUInteger idx))predicateBlock {
	NSParameterAssert(predicateBlock != nil);

	NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];

	[self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if (predicateBlock(obj, idx)) {
			[result addObject:obj];
		}
	}];

	return result.copy;
}



- (NSArray *)filteredArrayUsingBlock2:(BOOL (^)(id obj))predicateBlock { /// currently not used (testing)
	NSParameterAssert(predicateBlock != nil);

	return [self filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
		return predicateBlock(evaluatedObject);
	}]];
}


- (NSArray *)mappedArrayUsingBlock:(id (^)(id obj, NSUInteger idx, BOOL *stop))block {
	NSParameterAssert(block != nil);
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
	__block BOOL stop = NO;
	
	[self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *innerStop) {
		id mapped = block(obj, idx, &stop);
		if (mapped) {
			[result addObject:mapped];
		}
		if (stop) {
			*innerStop = YES;
		}
	}];
	
	return [result copy];
}


- (NSArray *)arrayByRemovingObject:(id)object {
	return [self filteredArrayUsingBlock:^BOOL(id  _Nonnull evaluatedObject, NSUInteger idx) {
		return evaluatedObject != object;
	}];
}


- (NSArray *)uniqueValuesForKeyPath:(NSString *)keyPath {
	NSMutableArray *result = NSMutableArray.new;
	NSMutableSet *seen = NSMutableSet.new;
	
	for (id obj in self) {
		id value = [obj valueForKeyPath:keyPath];
		if (value && ![seen containsObject:value]) {
			[result addObject:value];
			[seen addObject:value];
		}
	}
	return result;
}

-(nullable NSArray<NSIndexSet *> *)indexesOfDifferencesWithArray:(nullable NSArray *)array {
	NSInteger myCount = self.count;
	NSInteger otherCount = array.count;
	if((myCount > 1 && [NSSet setWithArray:self].count != myCount) || (otherCount > 1 && [NSSet setWithArray:array].count != otherCount)) {
		return nil;
	}
	
	if(myCount != otherCount && myCount >= 2 && otherCount >= 2) {
		NSArray *intersect = [self intersectionWithArray:array];
		if(intersect.count > 1 && ![intersect isEquivalentTo:[array intersectionWithArray:self]]) {
			return nil;
		}
	}
	
	if(myCount != otherCount || myCount == 0 || otherCount == 0) {
		NSIndexSet *indexesOfRemovals = [self indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			return [array indexOfObjectIdenticalTo:obj] == NSNotFound || array == nil;
		}];
		
		NSIndexSet *indexesOfInsertions = [array indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			return [self indexOfObjectIdenticalTo:obj] == NSNotFound;
		}];
		
		if(indexesOfRemovals.count > 0 && indexesOfInsertions.count > 0) {
			return nil;
		}
		return @[indexesOfRemovals, indexesOfInsertions? indexesOfInsertions:NSIndexSet.new];
	}
	
	NSMutableIndexSet *sourceIndexesDown = NSMutableIndexSet.new,
	*sourceIndexesUp = NSMutableIndexSet.new,
	*destinationIndexesDown = NSMutableIndexSet.new,
	*destinationIndexesUp = NSMutableIndexSet.new;
	
	[self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		NSInteger index = [array indexOfObject:obj];
		if(index > idx) {
			[sourceIndexesUp addIndex:idx];
			[destinationIndexesUp addIndex:index];
		} else if(index < idx) {
			[sourceIndexesDown addIndex:idx];
			[destinationIndexesDown addIndex:index];
		}
	}];
	
	NSInteger upCount = sourceIndexesUp.count, downCount = sourceIndexesDown.count;
	if(upCount + downCount == 0) {
		return @[sourceIndexesUp.copy, destinationIndexesUp.copy];
	}
	
	if((upCount != 1 && downCount != 1) || upCount == 0 || downCount == 0) {
		return nil;
	}
	
	NSInteger sourceIndex = upCount < downCount? sourceIndexesUp.firstIndex : sourceIndexesDown.firstIndex;
	NSInteger destinationIndex = upCount < downCount? destinationIndexesUp.firstIndex : destinationIndexesDown.firstIndex;

	NSMutableArray *mutable = self.mutableCopy;
	id obj = [self objectAtIndex:sourceIndex];
	[mutable removeObject:obj];
	[mutable insertObject:obj atIndex:destinationIndex];
	if([mutable isEquivalentTo:array]) {
		return @[[NSIndexSet indexSetWithIndex:sourceIndex],[NSIndexSet indexSetWithIndex:destinationIndex]];
	}
	return nil;
}


@end
