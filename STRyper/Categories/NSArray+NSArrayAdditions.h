//
//  NSArray+NSArrayAdditions.h
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



#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Convenience methods that `NSArray` does not implement.
@interface NSArray (NSArrayAdditions)

/// Returns an array that corresponds to the receiver, sorted using a key.
/// - Parameters:
///   - key: The key used for sorting. Members must responds to that key.
///   - ascending: Whether sorting is in ascending order.
-(NSArray *)sortedArrayUsingKey:(NSString *)key ascending:(BOOL)ascending;


/// Returns whether an array contains the same objects, in the same order, as the receiver.
/// - Parameter array: The array to compare.
///
/// Pointer identity is used.
-(BOOL) isEquivalentTo:(NSArray *) array;

/// Returns whether an array contains the objects of the receiver.
/// - Parameter array: The array to compare.
///
/// Pointer identity is used.
-(BOOL) containsSameObjectsAs:(NSArray *) array;

/// Convenience method that returns whether the receiver shares at least one object with another array.
///
/// Pointer equality is used for the test. 
/// - Parameter array: An array.
-(BOOL) sharesObjectsWithArray:(NSArray *)array;


/// Convenience method that returns whether the receiver contains all objects of another array.
///
/// Pointer equality is used for the test.
/// - Parameter array: An array.
-(BOOL) containsAllObjectsOf:(NSArray *)array;

/// Returns an array from which objects of another array are removed.
/// - Parameter array: An array.
-(NSArray *) arrayByRemovingObjectsIdenticalInArray:(NSArray *)array;

/// Returns an array from which objects that are equal to objects of another array are removed.
/// - Parameter array: An array.
-(NSArray *) arrayByRemovingObjectsInArray:(NSArray *)array;


/// Applies a test to each element of an array and returns those passing the test in a new array.
/// - Parameter predicateBlock: the block implementing the text. Its `idx` parameter is the index of `obj` in the array.
- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(id obj, NSUInteger idx))predicateBlock;

/// Returns an array from which objects that are identical to an object are removed.
/// - Parameter object: An object.
-(NSArray *) arrayByRemovingObject:(id)object;


/// Returns the unique values at a keypath for objects in the array, in the order of occurrence of each new value.
///
/// This method workarounds the fact that `@distinctUnionOfObjects` does not guarantee an order for the values.
/// - Parameter keyPath: A keypath for which objects in the array may return a value.
- (NSArray *)uniqueValuesForKeyPath:(NSString *)keyPath;

@end

NS_ASSUME_NONNULL_END
