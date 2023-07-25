//
//  NSPredicate+PredicateAdditions.m
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


#import "NSPredicate+PredicateAdditions.h"
#import "Chromatogram.h"
@implementation NSPredicate (PredicateAdditions)

- (nullable NSPredicate *)predicateWithFullDayComparisons {
	if([self isKindOfClass:NSCompoundPredicate.class]) {
		NSCompoundPredicate *compound = (NSCompoundPredicate *)self;
		NSMutableArray *subPredicates = [NSMutableArray arrayWithCapacity:compound.subpredicates.count];
		for(NSPredicate *pred in compound.subpredicates) {
			NSPredicate *result = [pred predicateWithFullDayComparisons];
			if(result) {
				[subPredicates addObject:result];
			} else {
				NSException *exception = [NSException exceptionWithName:@"Predicate conversion exception" reason:@"Failed to convert the search predicate." userInfo:@{NSLocalizedDescriptionKey: @"Unexpected Input."}];
				[exception raise];
				return nil;
			}
		}
		return [[NSCompoundPredicate alloc] initWithType:compound.compoundPredicateType subpredicates:subPredicates];
	}
	
	NSPredicate *modifiedPredicate = self;
	if([self isKindOfClass: NSComparisonPredicate.class]) {
		NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate *)self;
		NSExpression *rightExpr = comparisonPredicate.rightExpression;
		if([rightExpr.constantValue isKindOfClass: NSDate.class]) {
			NSDate *date = rightExpr.constantValue;
			
			/// we set the hour to 00:00:00 (by defaut, it is set to the hour at which the search was done, which may yield unexpected results)
			NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
			NSDate *morning = [[NSCalendar currentCalendar] dateFromComponents:components];
			
			/// we also need to represent the date 24 hours later
			NSDate *night = [morning dateByAddingTimeInterval:60*60*24];
			
			/// for equality or unequality comparisons to a day, we must modify the predicate operator type so that the whole day (from morning to night) can be matched or excluded
			/// for equality, we will generate a compound predicate that searches for dates >= morning AND < night
			NSInteger firstType = NSGreaterThanOrEqualToPredicateOperatorType;
			NSInteger secondType = NSLessThanPredicateOperatorType;
			NSInteger compoundType = NSAndPredicateType;
			date = morning;
			switch (comparisonPredicate.predicateOperatorType) {
				case NSNotEqualToPredicateOperatorType: {
					/// to exclude a given day, we generate a predicate that searches for dates < morning OR > night
					firstType = NSLessThanPredicateOperatorType;
					secondType = NSGreaterThanPredicateOperatorType;
					compoundType = NSOrPredicateType;
				}
				case NSEqualToPredicateOperatorType: {
					NSComparisonPredicate *first = [NSComparisonPredicate predicateWithLeftExpression:comparisonPredicate.leftExpression
																					  rightExpression:[NSExpression expressionForConstantValue:morning]
																							 modifier:comparisonPredicate.comparisonPredicateModifier
																								 type:firstType
																							  options:0];
					
					NSComparisonPredicate *second = [NSComparisonPredicate predicateWithLeftExpression:comparisonPredicate.leftExpression
																					   rightExpression:[NSExpression expressionForConstantValue:night]
																							  modifier:comparisonPredicate.comparisonPredicateModifier
																								  type:secondType
																							   options:0];
					
					modifiedPredicate = [[NSCompoundPredicate alloc] initWithType:compoundType subpredicates:@[first, second]];
				}
					break;
				case NSLessThanOrEqualToPredicateOperatorType:
				case NSGreaterThanPredicateOperatorType:
					/// when looking for dates after a given day, the reference hour is the night (same as for dates before or equal to the day)
					date = night;
				default:
					modifiedPredicate = [NSComparisonPredicate predicateWithLeftExpression:comparisonPredicate.leftExpression
																		   rightExpression:[NSExpression expressionForConstantValue:date]
																				  modifier:comparisonPredicate.comparisonPredicateModifier
																					  type:comparisonPredicate.predicateOperatorType
																				   options:0];
					break;
			}
		}
	}
	return modifiedPredicate;
}


- (nullable NSPredicate *)caseInsensitivePredicate {
	if([self isKindOfClass:NSCompoundPredicate.class]) {
		NSCompoundPredicate *compound = (NSCompoundPredicate *)self;
		NSMutableArray *subPredicates = [NSMutableArray arrayWithCapacity:compound.subpredicates.count];
		for(NSPredicate *pred in compound.subpredicates) {
			NSPredicate *result = [pred caseInsensitivePredicate];
			if(result) {
				[subPredicates addObject:result];
			} else {
				return nil;
			}
		}
		return [[NSCompoundPredicate alloc] initWithType:compound.compoundPredicateType subpredicates:subPredicates];
	}
	
	NSPredicate *modifiedPredicate = self;
	if([self isKindOfClass: NSComparisonPredicate.class]) {
		NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate *)self;
		NSExpression *rightExpr = comparisonPredicate.rightExpression;
		if([rightExpr.constantValue isKindOfClass: NSString.class]) {
			modifiedPredicate = [NSComparisonPredicate predicateWithLeftExpression:comparisonPredicate.leftExpression
																   rightExpression:comparisonPredicate.rightExpression
																		  modifier:comparisonPredicate.comparisonPredicateModifier
																			  type:comparisonPredicate.predicateOperatorType
																		   options:comparisonPredicate.options | NSCaseInsensitivePredicateOption];
		}
	}
	
	return modifiedPredicate;
	
}


- (BOOL)isCaseInsensitive {
	if([self isKindOfClass:NSCompoundPredicate.class]) {
		NSCompoundPredicate *compound = (NSCompoundPredicate *)self;
		for(NSPredicate *pred in compound.subpredicates) {
			if([pred isCaseInsensitive]) {
				return YES;
			}
		}
		return NO;
	}
	
	if([self isKindOfClass: NSComparisonPredicate.class]) {
		NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate *)self;
		return comparisonPredicate.options & NSCaseInsensitivePredicateOption;
	}
	return NO;
}


-(BOOL)hasEmptyTerms {
	if([self isKindOfClass:NSCompoundPredicate.class]) {
		NSCompoundPredicate *compound = (NSCompoundPredicate *)self;
		for(NSPredicate *pred in compound.subpredicates) {
			if([pred hasEmptyTerms]) {
				return YES;
			}
		}
		return NO;
	}
	
	if([self isKindOfClass: NSComparisonPredicate.class]) {
		NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate *)self;
		id value = comparisonPredicate.rightExpression.constantValue;
		if([value respondsToSelector:@selector(length)] && [value length] == 0) {
			return YES;
		}
	}
	return NO;
}


@end
