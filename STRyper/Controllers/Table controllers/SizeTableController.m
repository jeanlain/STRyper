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



- (NSDictionary *)columnDescription {
	NSDictionary *columnDescription = @{
		@"sizeColumn":	@{KeyPathToBind: @"size",ColumnTitle: @"Sizes", CellViewID:@"sizeCellView",
						  IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES,
						  IsColumnSortingCaseInsensitive: @NO}
	};
	
	return columnDescription;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	return @[@"sizeColumn"];
}


-(void)viewDidLoad {
	[super viewDidLoad];
	NSMenu *menu = NSMenu.new;
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Edit Size" action:@selector(rename:) keyEquivalent:@""];
	item.offStateImage = [NSImage imageNamed:ACImageNameEdited];
	item.target = self;
	[menu addItem:item];
	item = [[NSMenuItem alloc] initWithTitle:@"Delete" action:@selector(remove:) keyEquivalent:@""];
	item.offStateImage = [NSImage imageNamed:ACImageNameTrash];
	item.target = self;
	[menu addItem:item];
	self.tableView.menu = menu;
	menu.delegate = self;
}


- (NSString *)actionNameForEditingCellInColumn:(NSTableColumn *)column row:(NSInteger)row {
	return @"Change Fragment Size";
}


- (BOOL)canRenameItem:(id)item {
	if([item respondsToSelector:@selector(sizeStandard)]) {
		SizeStandard *selectedStandard = [item sizeStandard];
		return selectedStandard.editable;
	}
	return NO;
}


-(IBAction)newSize:(id)sender {
	SizeStandard *selectedStandard = SizeStandardTableController.sharedController.tableContent.selectedObjects.firstObject;
	if(!selectedStandard.editable || !self.tableContent.canInsert) {
		return;
	}
	
	SizeStandardSize *selectedFragment = self.tableContent.selectedObjects.firstObject;
	short newSize = selectedFragment.size + 1;
	if(newSize < 10) {
		newSize = 10;
	}
	
	[self.undoManager setActionName:@"New Size"];
	SizeStandardSize *newFragment = [[SizeStandardSize alloc] initWithContext:self.tableContent.managedObjectContext];
	newFragment.size = newSize;
	
	NSInteger selectedIndex = self.tableContent.selectionIndexes.lastIndex;
	if(selectedIndex == NSNotFound) {
		selectedIndex = -1;
	}
	[self.tableContent insertObject:newFragment atArrangedObjectIndex:selectedIndex+1];
	[newFragment autoSize];		/// to avoid duplicated or illegal sizes
	[self selectItemName:newFragment];
	
}


- (NSString *)deleteActionTitleForItems:(NSArray *)items {
	SizeStandard *selectedStandard = SizeStandardTableController.sharedController.tableContent.selectedObjects.firstObject;
	if(!selectedStandard.editable) {
		return nil;
	}
	return [super deleteActionTitleForItems:items];
}


- (NSString *)cannotDeleteInformativeStringForItems:(NSArray *)items {

	SizeStandardSize *fragment = items.firstObject;
	SizeStandard *standard = fragment.sizeStandard;
	if(standard && (!standard.editable || (standard.sizes.count - items.count < 4))) {
		NSString *informativeText = @"This size standard cannot be modified.";
		if(standard.sizes.count - items.count < 4) {
			informativeText = @"A size standard cannot have less than 4 sizes.\n You may leave at least 4 sizes and modify their values.";
		}
		return informativeText;
	}
	return nil;

}

@end
