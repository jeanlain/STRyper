//
//  MarkerTableController.m
//  STRyper
//
//  Created by Jean Peccoud on 06/08/2022.
//
// an object of this class controls the tableview showing markers
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



#import "MarkerTableController.h"
#import "MainWindowController.h"
#import "Mmarker.h"
#import "IndexImageView.h"
#import "SampleTableController.h"
#import "PanelListController.h"
#import "NewMarkerPopover.h"
#import "Genotype.h"




@interface MarkerTableController ()

@property (nonatomic) NSDictionary *actionNamesForColumnIDs;

@end


@implementation MarkerTableController {
		NewMarkerPopover *newMarkerPopover;    	/// spawned when the users clicks the + button to add a marker. 
												/// Since we manage panels and panels have markers, we also control the addition of markers (this may be moved to another class)

}


- (NSString *)entityName {
	return Mmarker.entity.name;
}

- (NSString *)nameForItem:(id)item {
	return @"Marker";
}

/// To represent the channel of a marker by an image in the cell of the table
static NSArray *channelColorImages;


+ (NSArray *)channelColorImages {
	if(!channelColorImages) {
		channelColorImages = @[[NSImage imageNamed:ACImageNameShowBlueDye],
							  [NSImage imageNamed:ACImageNameShowGreenDye],
							  [NSImage imageNamed:ACImageNameShowBlackDye],
							  [NSImage imageNamed:ACImageNameShowRedDye],
							  [NSImage imageNamed:ACImageNameShowOrangeDye]
		];
	}
	return channelColorImages;
}


- (void)viewDidLoad {
	[super viewDidLoad];
	NSMenu *menu = NSMenu.new;
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
	item.image = [NSImage imageNamed:ACImageNameCopy];
	item.target = self;
	[menu addItem:item];
	item = [[NSMenuItem alloc] initWithTitle:@"Delete" action:@selector(remove:) keyEquivalent:@""];
	item.image = [NSImage imageNamed:ACImageNameTrash];
	item.target = self;
	[menu addItem:item];
	self.tableView.menu = menu;
	menu.delegate = self;
}


# pragma mark - composing the marker table

- (NSDictionary *)columnDescription {
	static NSDictionary *columnDescription = nil;
	if(!columnDescription) {
		columnDescription = @{
			@"markerNameColumn":	@{KeyPathToBind: @"name",ColumnTitle: @"Marker", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Name of marker"},
			@"markerChannelColumn":	@{KeyPathToBind: @"channelName", ImageIndexBinding: @"channel" ,ColumnTitle: @"Dye color", CellViewID: @"compositeCellViewText", IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Color of the marker's dye"},
			@"markerStartColumn":		@{KeyPathToBind: @"start",ColumnTitle: @"Start", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Start of the marker's range"},
			@"markerEndColumn":		@{KeyPathToBind: @"end",ColumnTitle: @"End", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"End of the marker's range"},
			/// For the column below, the cell view prototype is in a different table and we don't use the cell view ID
			@"markerMotiveColumn":		@{KeyPathToBind: @"motiveLength",ColumnTitle: @"Motive", CellViewID: @"", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Length of the marker's repeat motive"},
			@"markerPloidyColumn":		@{KeyPathToBind: @"ploidy",ColumnTitle: @"Ploidy", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Ploidy of the marker:\n1 for haploid, 2 for diploid"}
		};
	}
	return columnDescription;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	return @[@"markerNameColumn", @"markerChannelColumn", @"markerStartColumn", @"markerEndColumn", @"markerMotiveColumn", @"markerPloidyColumn"];
}



- (NSInteger)itemNameColumn {	
	return [self.tableView.tableColumns indexOfObjectPassingTest:^BOOL(NSTableColumn * _Nonnull column, NSUInteger idx, BOOL * _Nonnull stop) {
		return [column.identifier isEqualToString:@"markerNameColumn"];
	}];
}



- (NSString *)actionNameForEditingCellInColumn:(NSTableColumn *)column row:(NSInteger)row {
	NSString *actionName = self.actionNamesForColumnIDs[column.identifier];
	if(actionName) {
		return actionName;
	}
	return [super actionNameForEditingCellInColumn:column row:row];
}


- (NSDictionary *)actionNamesForColumnIDs {
	if(!_actionNamesForColumnIDs) {
		_actionNamesForColumnIDs = @{@"markerNameColumn": @"Rename Marker",
									 @"markerStartColumn": @"Resize Marker",
									 @"markerEndColumn": @"Resize Marker",
									 @"markerMotiveColumn": @"Change Marker Motive Length"
		};
	}
	return _actionNamesForColumnIDs;
}



- (NSTableView *)viewForCellPrototypes {
	return SampleTableController.sharedController.tableView;
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *ID = tableColumn.identifier;

	if([ID isEqualToString:@"markerMotiveColumn"]) {
		NSTableCellView *view = [self.tableView makeViewWithIdentifier:ID owner:self];
		return view;
	}
	
	NSTableCellView *view = (NSTableCellView *)[super tableView:tableView viewForTableColumn:tableColumn row:row];

	if([ID isEqualToString:@"markerChannelColumn"]) {
		IndexImageView *imageView = (IndexImageView *)view.imageView;
		if([imageView respondsToSelector:@selector(imageArray)] && imageView.imageArray == nil) {
			imageView.imageArray = self.class.channelColorImages;
		}
	}
	
	return view;
}


# pragma mark - dragging and copying markers

- (void)copyItems:(NSArray *)items ToPasteBoard:(NSPasteboard *)pasteboard {
	[super copyItems:items ToPasteBoard:pasteboard];
	[pasteboard writeObjects:items];
}



- (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	NSArray *genotypes = [items valueForKeyPath:@"@unionOfSets.genotypes"];
	if(genotypes.count > 0) {
		return  @"All genotypes at the marker will be deleted as well. \nThis action can be undone.";
	}
	
	return [super cautionAlertInformativeStringForItems:items];
}


- (NSString *)exportActionTitleForItems:(NSArray *)items {
	/// We don't export individual markers, but we can export their source panel.
	Panel *selectedPanel = PanelListController.sharedController.selectedFolder;
	if(selectedPanel) {
		return [PanelListController.sharedController exportActionTitleForItems:@[selectedPanel]];
	}
	return nil;
}



- (NSImage *)exportButtonImageForItems:(NSArray *)items {
	return [PanelListController.sharedController exportButtonImageForItems:items];
}



- (void)exportSelection:(id)sender {
	[PanelListController.sharedController exportSelection:sender];
}

# pragma mark - adding markers

/// spawns the popover allowing to define a new marker.
/// Triggered by the "+" button below the panel outline view to add a marker via popover
- (IBAction)newMarkerPrompt:(id)sender {
	if(!newMarkerPopover) {
		newMarkerPopover = NewMarkerPopover.popover;
		newMarkerPopover.behavior = NSPopoverBehaviorTransient;
		newMarkerPopover.okAction = @selector(addMarker:);
		newMarkerPopover.okActionTarget = self;
	}
	if(newMarkerPopover) {
		PanelListController *controller = PanelListController.sharedController;
		Panel *panel = controller.selectedFolder;
		if(!panel || !panel.isPanel) {
			return;		/// a marker can only be added to a panel, not a folder
						/// this is a safety measure, as the button to add a marker should only be enabled if a panel is selected
		}
		
		/// we populate the field with a proposed name that avoids duplicates (see Panel class)
		newMarkerPopover.markerName = [panel proposedMarkerName];
		newMarkerPopover.diploid = YES;					/// which correspond to diploid
		NSButton *button = (NSButton *)sender;
		[newMarkerPopover showRelativeToRect:button.frame ofView:button.superview preferredEdge:NSRectEdgeMaxY modal:NO];
	}
}

/// Triggered by the "add marker" button on the popover. Adds a marker and save it in the selected panel if it is valid
- (IBAction)addMarker:(id)sender {

	NSError *error;
	/// we add the marker in a background context. We won't save if the marker is not valid.
	NSManagedObjectContext *MOC = AppDelegate.sharedInstance.newChildContextOnMainQueue;
	
	PanelListController *controller = PanelListController.sharedController;
	Panel *panel = controller.selectedFolder;

	/// the panel to add the marker to must be materialized in this context
	if(!panel) {
		return;
	}
	
	if(panel.objectID.isTemporaryID) {
		[panel.managedObjectContext obtainPermanentIDsForObjects:@[panel] error:&error];
		if(error) {
			error = [NSError errorWithDescription:@"The marker could not be created because of an inconsistency in the database." suggestion:@""];
		}
	}
	
	if(!error) {
		panel = [MOC existingObjectWithID:panel.objectID error:&error];
		if(error) {
			error = [NSError errorWithDescription:@"The marker could not be created because an error occurred in the database." suggestion:@"You may restart the application and try again."];
		}
	}

	if(error) {
		[NSApp presentError:error];
		return;
	}


	Mmarker *newMarker = [[Mmarker alloc] initWithStart:newMarkerPopover.markerStart end:newMarkerPopover.markerEnd
												channel:newMarkerPopover.markerChannel ploidy:newMarkerPopover.diploid+1 panel:panel];
	newMarker.name = newMarkerPopover.markerName;
	newMarker.motiveLength = newMarkerPopover.motiveLength;
	
	[newMarker validateForUpdate:&error];
	if(error) {
		NSArray *errors = (error.userInfo)[NSDetailedErrorsKey];
		if(errors.count > 0) {
			error = errors.firstObject;
		}
		[NSApp presentError:error];
		return;
	}
	
	[newMarker createGenotypesWithAlleleName: [NSUserDefaults.standardUserDefaults stringForKey:MissingAlleleName]];
	
	[self.undoManager setActionName:@"Add Marker"];
	BOOL saved = [MOC save:nil];
	if(saved) {
		[AppDelegate.sharedInstance saveAction:self];
	} else {
		error = [NSError errorWithDescription:@"The marker could not be created because an inconsistency in the database." suggestion:@"You may quit the application and try again."];
		[NSApp presentError:error];
	}
	
	[newMarkerPopover close];
	
}



@end
