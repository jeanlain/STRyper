//
//  SearchWindow.m
//  STRyper
//
//  Created by Jean Peccoud on 26/02/2023.
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


#import "SearchWindow.h"
#import "NSPredicate+PredicateAdditions.h"
#import "NSError+NSErrorAdditions.h"

@implementation SearchWindow {
	
	/// The predicate editor shown, backs the readonly variable.
	__weak IBOutlet NSPredicateEditor *_predicateEditor;
	
	/// The checkbox of the search window allowing to set case sensitivity.
	__weak IBOutlet NSButton *_caseSensitiveOptionCheckBox;
	
	/// The text field showing the message on top of the window.
	__weak IBOutlet NSTextField *messageTextField;

}


@synthesize predicateEditor = _predicateEditor, caseSensitiveOptionCheckBox = _caseSensitiveOptionCheckBox;


+ (nullable instancetype)searchWindow {
	NSArray *objects;
	if([NSBundle.mainBundle loadNibNamed:@"SearchWindow" owner:nil topLevelObjects:&objects]) {
		for(id object in objects) {
			if([object isKindOfClass: [self class]]) {
				return object;
			}
		}
		return nil;
	}
	return nil;
}


- (instancetype)init {
	return [self.class searchWindow];
}


- (void)setMessage:(NSString *)message {
	messageTextField.stringValue = [message copy];
}


- (NSString *)message {
	return messageTextField.stringValue;
}


- (void)setPredicate:(NSPredicate *)predicate {
	_caseSensitiveOptionCheckBox.state = predicate.isCaseInsensitive;
	self.predicateEditor.objectValue = predicate;
}


- (NSPredicate *)predicate {
	NSPredicate *predicate = self.predicateEditor.predicate;
	if(_caseSensitiveOptionCheckBox.state == NSControlStateValueOn) {
		predicate = predicate.caseInsensitivePredicate;
	}
	return predicate;
}

/// Sent by the Ok or Cancel button 
- (IBAction)validateSearch:(NSButton *)sender {
	NSModalResponse returnCode = [sender.title isEqualToString:@"OK"]? NSModalResponseOK : NSModalResponseCancel;
	
	if(returnCode == NSModalResponseOK && self.predicateEditor) {
		NSPredicate *predicate = self.predicateEditor.predicate;
		/// we won't close if the predicate has empty terms
		if(predicate.hasEmptyTerms) {
			NSError *error = [NSError errorWithDescription:@"At least one text field is empty." suggestion:@"Please, fill all fields."];
			[[NSAlert alertWithError:error] beginSheetModalForWindow:self completionHandler:^(NSModalResponse returnCode) {
			}];
			return;
		}
	}
	
	NSWindow *parentWindow = [self sheetParent];
	
	if(parentWindow) {
		[parentWindow endSheet:self returnCode:returnCode];
	} else {
		[self close];
	}
}


@end



