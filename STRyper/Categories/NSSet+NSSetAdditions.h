//
//  NSSet+NSSetAdditions.h
//  STRyper
//
//  Created by Jean Peccoud on 29/05/2023.
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

/// This category adds a method to quickly returns if the receiver contains a given object.
@interface NSSet (NSSetAdditions)

/// Returns whether the receiver contains an object.
///
/// The returns whether the receiver contains `object` by checking pointer equality.
/// - Parameter object: The object for which to check the presence in the set.
- (BOOL) hasObject:(id) object;

@end

NS_ASSUME_NONNULL_END
