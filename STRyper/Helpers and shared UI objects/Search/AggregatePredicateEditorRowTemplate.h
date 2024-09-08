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
/// compares all entries of the destination of the to-many relationship (`NSAllPredicateModifier`) or matches any entry (`NSAnyPredicateModifier`).
/// This control is added to the template views only if the object's `modifier` is one of the above modifiers.
/// The predicate to set must be an `NSComparisonPredicate` containing a left expression, a right expression and a comparison modifier.
///
/// - Important: By default, the segmented control is positioned at the right of the left popup button of the template.
/// To place it at the left, the key of the predicate editor formatting dictionary should look like `%[keypath]@ %@ %@ %@`
/// and the value should look like `%2$@ %1$[Menu Item Title ]@ %3$@ %4$@`
///
/// An `AggregatePredicateEditorRowTemplate` also brings improvement when using a predicate based on a float value:
/// it adds a number formatter to the text field, which it makes wider (by default, it is too narrow).
@interface AggregatePredicateEditorRowTemplate : NSPredicateEditorRowTemplate


@end

NS_ASSUME_NONNULL_END
