//
//  AggregatePredicateEditorRowTemplate.h
//  STRyper
//
//  Created by Jean Peccoud on 03/08/2023.
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

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A predicate editor row template that allows to define a comparison predicate modifier for a to-many relationship.
///
/// An `AggregatePredicateEditorRowTemplate` adds a segmented control that allows to specify wether the predicate
/// compares all entries of the destination of the to-many relationship (`NSAllPredicateModifier`) or matches with any entry (`NSAllPredicateModifier`).
/// This button is not added if the object's `modifier` is not one of the above modifiers.
/// The predicate to set must be an `NSComparisonPredicate` containing a left expression, a right expression and a comparison modifier.
@interface AggregatePredicateEditorRowTemplate : NSPredicateEditorRowTemplate


@end

NS_ASSUME_NONNULL_END
