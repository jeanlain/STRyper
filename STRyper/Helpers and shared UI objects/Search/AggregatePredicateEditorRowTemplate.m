//
//  AggregatePredicateEditorRowTemplate.m
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


#import "AggregatePredicateEditorRowTemplate.h"

@interface AggregatePredicateEditorRowTemplate ()

/// The controls that allows defining the modifiers of the predicate
@property (nonatomic) NSSegmentedControl *modifierControl;
@property (nonatomic) NSNumberFormatter *formatter;

@end


NS_ENUM(NSUInteger, SelectedSegmentIndex) {
	AnyPredicateModifierIndex = 0,
	AllPredicateModifierIndex = 1,
} ;


@implementation AggregatePredicateEditorRowTemplate

- (NSSegmentedControl *)modifierControl {
	if(!_modifierControl) {
		_modifierControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Any", @"All"]
															 trackingMode:NSSegmentSwitchTrackingSelectOne
																   target:nil
																   action:nil];
		_modifierControl.controlSize = NSControlSizeSmall;
		_modifierControl.segmentStyle = NSSegmentStyleRounded;
		_modifierControl.selectedSegment = AnyPredicateModifierIndex;
	}
	return _modifierControl;
}


- (NSNumberFormatter *)formatter {
	if(!_formatter) {
		_formatter = NSNumberFormatter.new;
		_formatter.numberStyle = NSNumberFormatterDecimalStyle;
		_formatter.roundingMode = NSNumberFormatterRoundHalfDown;
		_formatter.maximumFractionDigits = 3;
	}
	return _formatter;
}


- (NSArray<NSView *> *)templateViews {
	NSArray *views = super.templateViews;
	if(self.rightExpressionAttributeType == NSFloatAttributeType) {
		for(NSView *view in views) {
			if([view isKindOfClass:NSTextField.class]) {
				NSTextField *textField = (NSTextField *)view;
				if(textField.isEditable) {
					if(!textField.formatter) {
						textField.formatter = self.formatter;
						textField.tag = -666;
					}
					NSSize frameSize = textField.frame.size;
					if(frameSize.width < 100) {
						frameSize.width = 100;
						[textField setFrameSize:frameSize];
					}
				}
			}
		}
	}
	
	NSSegmentedControl *control = self.modifierControl;
	if(self.modifier == NSAnyPredicateModifier || self.modifier == NSAllPredicateModifier) {
		NSMutableArray *templateViews = views.mutableCopy;
		/// If we insert the segmented control as first view, the template will not display.
		/// So we insert it as the second view (after the left popup button). The formatting dictionary of the editor may place it at the left.
		[templateViews insertObject:control atIndex:1];
		return templateViews.copy;
	}
	
	return views;
}


- (void)setPredicate:(NSPredicate *)predicate {
	if([predicate isKindOfClass:NSComparisonPredicate.class]) {
		NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate *)predicate;
		NSComparisonPredicateModifier modifier = comparisonPredicate.comparisonPredicateModifier;
		if(modifier == NSAllPredicateModifier) {
			self.modifierControl.selectedSegment = AllPredicateModifierIndex;
		} else if(modifier == NSAnyPredicateModifier) {
			self.modifierControl.selectedSegment = AnyPredicateModifierIndex;
		} else {
			self.modifierControl.selectedSegment = -1;
		}
	}
	super.predicate = predicate;
}


- (NSPredicate *)predicateWithSubpredicates:(NSArray<NSPredicate *> *)subpredicates {
	NSPredicate *predicate = [super predicateWithSubpredicates:subpredicates];
	if([predicate isKindOfClass:NSComparisonPredicate.class]) {
		NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate *)predicate;
		if(comparisonPredicate.leftExpression && comparisonPredicate.rightExpression && comparisonPredicate.comparisonPredicateModifier) {
			NSComparisonPredicateModifier modifier = self.modifierControl.selectedSegment == AllPredicateModifierIndex? NSAllPredicateModifier : NSAnyPredicateModifier;
			
			return [NSComparisonPredicate predicateWithLeftExpression:comparisonPredicate.leftExpression
													  rightExpression:comparisonPredicate.rightExpression
															 modifier:modifier
																 type:comparisonPredicate.predicateOperatorType
															  options:comparisonPredicate.options];
		}
	}
	return predicate;
}


@end
