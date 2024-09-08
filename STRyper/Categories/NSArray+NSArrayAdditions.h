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

@interface NSArray (NSArrayAdditions)


-(NSArray *)sortedArrayUsingKey:(NSString *)key ascending:(BOOL)ascending;


/// Returns whether an array contains the same objects, in the same order, as the receiver.
/// - Parameter array: The array to compare.
-(BOOL) isIdenticalTo:(NSArray *) array;

/// Convenience method that returns whether the receiver shares at least one object with another array.
///
/// Pointer equality is used for the test. 
/// - Parameter array: An array.
-(BOOL) sharesObjectsWithArray:(NSArray *)array;

/// Returns an array from which objects of another array are removed.
/// - Parameter array: An array.
-(NSArray *) arrayByRemovingObjectsIdenticalInArray:(NSArray *)array;

/// Returns an array from which objects that are equal to objects of another array are removed.
/// - Parameter array: An array.
-(NSArray *) arrayByRemovingObjectsInArray:(NSArray *)array;


@end

NS_ASSUME_NONNULL_END
