//
//  SizeStandardTableController.m
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



#import "SizeStandardTableController.h"
#import "SizeStandard.h"
#import "SizeStandardSize.h"
@class SizeTableController;


NSString * _Nonnull const SizeStandardDragType = @"org.jpeccoud.stryper.sizeStandardDragType";	/// used when copying a size standard to the pasteboard.

@implementation SizeStandardTableController {
		IBOutlet SizeTableController *sizeController;  	/// to retain this controller, which is a top-level object of the nib we own
}

+ (instancetype)sharedController {
	static SizeStandardTableController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = [[self alloc] init];
	});
	return controller;
}


- (instancetype)init {
	return [super initWithNibName:@"SizeStandardTab" bundle:nil];
}


- (NSString *)entityName {
	return SizeStandard.entity.name;
}

- (NSString *)nameForItem:(id)item {
	return @"Size Standard";
}



- (void)viewDidLoad {
	[super viewDidLoad];
	/// we create the "factory" size standards if needed
	AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
	NSManagedObjectContext *MOC = appDelegate.managedObjectContext;
	
	NSDictionary *factoryStandards = @{@"GeneScan-500":@[@35, @50, @75, @100, @139, @150, @160, @200, @300, @340, @350, @400, @450, @490, @500], /// note that we removed size 250, which is unreliable
									   @"GeneScan-400HD":@[@50, @60, @90, @100, @120, @150, @160, @180, @190, @200, @220, @240, @260, @280, @290, @300, @320, @340, @360, @380, @400],
									   @"GeneScan-350":@[@35, @50, @75, @100, @139, @150, @160, @200, @250, @300, @340, @350],
									   @"GeneScan-600": @[@20, @40, @60, @80, @100, @114, @120, @140, @160, @180, @200, @214, @220, @240, @250, @260, @280, @300, @314, @320, @340, @360, @380, @400, @414, @420, @440, @460, @480, @500, @514, @520, @540, @560, @580, @600],
									   @"GeneScan-1000" : @[@47, @51, @55, @82, @85, @93, @99, @126, @136, @262, @293, @317, @439, @557, @692, @695, @946],
									   @"GeneScan-1200": @[@40, @60, @80, @100, @114, @120, @140, @160, @180, @200, @214, @220, @240, @250, @260, @280, @300, @314, @320, @340, @360, @380, @400, @414, @420, @440, @460, @480, @500, @514, @520, @540, @560, @580, @600, @614, @620, @640, @660, @680, @700, @714, @720, @740, @760, @780, @800, @820, @840, @850, @860, @880, @900, @920, @940, @960, @980, @1000, @1020, @1040, @1060, @1080, @1100, @1120, @1160, @1200],
									   @"Promega-ILS-600" : @[@60, @80, @100, @120, @140, @160, @180, @200, @225, @250, @275, @300, @325, @350, @375, @400, @425, @450, @475, @500, @550, @600]
	};
	
	
	for (NSString *name in factoryStandards) {
		NSFetchRequest *fetchRequest =  [appDelegate.persistentContainer.managedObjectModel fetchRequestFromTemplateWithName:@"exactSizeStandardName" substitutionVariables:@{@"SIZE_STANDARD_NAME": name}];
		NSArray *fetchedSizeStandard = [MOC executeFetchRequest:fetchRequest error:nil];
		if(fetchedSizeStandard.count == 0) { 					///if there is no factory standard with this name
			SizeStandard *newStandard =  [[SizeStandard alloc] initWithEntity:SizeStandard.entity insertIntoManagedObjectContext:MOC];
			newStandard.name = name;
			newStandard.editable = NO;
			for (NSNumber *size in factoryStandards[name]) { 	///we populate the standard with fragments
				SizeStandardSize *fragment = [[SizeStandardSize alloc] initWithEntity:SizeStandardSize.entity insertIntoManagedObjectContext:MOC];
				fragment.size = size.intValue;
				fragment.sizeStandard = newStandard;
			}
		}
	}
}


/// We allow dragging a size standard onto samples
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
	if(row > [self.tableContent.arrangedObjects count]) {
		return nil;
	}
	SizeStandard *draggedSizeStandard = [self.tableContent.arrangedObjects objectAtIndex:row];;
	if(draggedSizeStandard.objectID.isTemporaryID) {
		[draggedSizeStandard.managedObjectContext obtainPermanentIDsForObjects:@[draggedSizeStandard] error:nil];
	}
	NSPasteboardItem *pasteBoardItem = NSPasteboardItem.new;
	[pasteBoardItem setString:draggedSizeStandard.objectID.URIRepresentation.absoluteString forType:SizeStandardDragType];
	return pasteBoardItem;
	
}


- (BOOL)canRenameItem:(id)item {
	if([item respondsToSelector:@selector(editable)]) {
		return [item editable];
	}
	return NO;
}


- (BOOL)canAlwaysRemove {
	return NO;				/// non-editable size standards cannot be removed
}


- (nullable NSAlert *)cannotRemoveAlertForItems:(NSArray *)items {

	SizeStandard *standard = items.firstObject;		/// there can be only one item, as the table doesn't allow multiple selection
	if(!standard || standard.editable) {
		return nil;			/// there is no alert if the size standard to remove is editable
	}
	return [super cannotRemoveAlertForItems:items];

}


- (NSString *)removeActionTitleForItems:(NSArray *)items {
	id item = items.firstObject;
	if([item respondsToSelector:@selector(editable)]) {
		if([item editable]) {
			return [super removeActionTitleForItems:items];
		}
	}
	return nil;
}


- (NSString *)cannotRemoveInformativeStringForItems:(NSArray *)items {
	return @"This size standard is part of the default set.";
}


- (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	return  @"You will no longer be able to use this size standard. \nThis action can be undone.";
}


- (IBAction)duplicateStandard:(id)sender {
	NSArray *selectedObjects = self.tableContent.selectedObjects;
	if (selectedObjects.count > 0) {
		SizeStandard *initialStandard = selectedObjects.firstObject;
		SizeStandard *duplicateStandard = [initialStandard copy];
		duplicateStandard.editable = YES;
		[duplicateStandard autoName];
		[self.tableContent addObject:duplicateStandard];
		[self selectItemName:duplicateStandard];
	//	[self addObject:duplicateStandard]; /// required to automatically select the name
		[self.undoManager setActionName:@"Duplicate Size Standard"];
	}
}



@end
