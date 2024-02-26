//
//  SizeTableController.m
//  STRyper
//
//  Created by Jean Peccoud on 06/08/2022.
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



#import "SizeTableController.h"
#import "SizeStandardSize.h"
#import "SizeStandard.h"
#import "SizeStandardTableController.h"

@implementation SizeTableController



- (NSString *)entityName {
	return SizeStandardSize.entity.name;
}


- (NSString *)nameForItem:(id)item {
	return @"Size";
}


- (NSString *)actionNameForEditingCellInColumn:(NSTableColumn *)column {
	return @"Change Fragment Size";
}


- (BOOL)canAlwaysRemove {
	return NO;				/// fragments from a non-editable size standard cannot be removed
}


- (nullable NSAlert *)cautionAlertForRemovingItems:(NSArray *)items {
	return nil;
}


-(IBAction)newSize:(id)sender {
	SizeStandard *selectedStandard = SizeStandardTableController.sharedController.tableContent.selectedObjects.firstObject;
	if(!selectedStandard.editable || !self.tableContent.canInsert) {
		return;
	}
	
	SizeStandardSize *selectedFragment = self.tableContent.selectedObjects.firstObject;
	short newSize = selectedFragment.size + 1;
	if(newSize < 20) {
		newSize = 20;
	}
	
	SizeStandardSize *newFragment = [[SizeStandardSize alloc] initWithContext:self.tableContent.managedObjectContext];
	newFragment.size = newSize;
	
	NSInteger selectedIndex = self.tableContent.selectionIndexes.lastIndex;
	if(selectedIndex == NSNotFound) {
		selectedIndex = -1;
	}
	[self.tableContent insertObject:newFragment atArrangedObjectIndex:selectedIndex+1];
	[newFragment autoSize];		/// to avoid duplicated or illegal sizes
	[self selectItemName:newFragment];
	
	[self.undoManager setActionName:@"New Size"];
}


- (NSAlert *)cannotRemoveAlertForItems:(NSArray *)items {

	SizeStandardSize *fragment = items.firstObject;
	SizeStandard *standard = fragment.sizeStandard;
	if(standard && (!standard.editable || (standard.sizes.count - items.count < 4))) {
		NSAlert *alert = [super cannotRemoveAlertForItems:items];
		NSString *informativeText = @"This size standard cannot be modified.";
		if(standard.sizes.count - items.count < 4) {
			informativeText = @"A size standard cannot have less than 4 sizes.\n You may leave at least 4 sizes and modify their values.";
		}
		alert.informativeText = informativeText;
		return alert;
	}
	return nil;

}

@end
