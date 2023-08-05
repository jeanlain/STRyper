//
//  NSPredicate+PredicateAdditions.h
//  STRyper
//
//  Created by Jean Peccoud on 07/01/2023.
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

/// some addition that we use in sample searches
@interface NSPredicate (PredicateAdditions)


/// Returns a predicate that is equivalent to the receiver, except that date comparisons corresponding to entire days.
///
/// This method works around the fact that NSDate is specific to the second.
- (nullable NSPredicate *)predicateWithFullDayComparisons;

/// Returns a predicate that is equivalent to the receiver, expect that it has case insensitive options.
- (nullable NSPredicate *)caseInsensitivePredicate;

/// Whether the receiver has at least one component corresponding to a case-insensitive search.
- (BOOL) isCaseInsensitive;

/// Tells if the receiver has empty search terms (right expressions).
- (BOOL) hasEmptyTerms;

@end

NS_ASSUME_NONNULL_END
