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
		channelColorImages = @[[NSImage imageNamed:@"showBlueDye"],
							  [NSImage imageNamed:@"showGreenDye"],
							  [NSImage imageNamed:@"showBlackDye"],
							  [NSImage imageNamed:@"showRedDye"],
		];
	}
	return channelColorImages;
}


- (void)viewDidLoad {
	[super viewDidLoad];
	NSMenu *menu = NSMenu.new;
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
	item.offStateImage = [NSImage imageNamed:@"copy"];
	item.target = self;
	[menu addItem:item];
	item = [[NSMenuItem alloc] initWithTitle:@"Delete" action:@selector(remove:) keyEquivalent:@""];
	item.offStateImage = [NSImage imageNamed:@"trash"];
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
			@"markerNameColumn":	@{KeyPathToBind: @"name",ColumnTitle: @"Marker", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES},
			@"markerChannelColumn":	@{KeyPathToBind: @"channelName", ImageIndexBinding: @"channel" ,ColumnTitle: @"Dye color", CellViewID: @"compositeCellViewText", IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			@"markerStartColumn":		@{KeyPathToBind: @"start",ColumnTitle: @"Start", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			@"markerEndColumn":		@{KeyPathToBind: @"end",ColumnTitle: @"End", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			/// For the column below, the cell view prototype is in a different table and we don't use the cell view ID
			@"markerMotiveColumn":		@{KeyPathToBind: @"motiveLength",ColumnTitle: @"Motive", CellViewID: @"", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			@"markerPloidyColumn":		@{KeyPathToBind: @"ploidy",ColumnTitle: @"Ploidy", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO}
		};
	}
	return columnDescription;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	/// a column with id @"markerNameColumn" is already set in the nib.
	/// This is because the table shifts to cell-based if it doesn't have a column in Xcode 14. 
	/// So it must have a column, and we don't add it to the identifiers
	return @[@"markerChannelColumn", @"markerStartColumn", @"markerEndColumn", @"markerMotiveColumn", @"markerPloidyColumn"];
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
		if([view.imageView respondsToSelector:@selector(imageArray)]) {
			((IndexImageView *)view.imageView).imageArray = self.class.channelColorImages;
		}
	}
	
	return view;
}


# pragma mark - dragging markers

/// we allow copy-dragging markers between panels
- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes {
	/// here we set images representing markers being dragged
	/// If we don't, images would correspond to the cells of the column being clicked at the beginning of the drag,
	/// which may not indicate the marker name. Instead, it could be size,  ploidy...
	/// We use image components that indicate the marker's dye and its name.
	/// The former is the colored icon showing in the cell indicating the dye (which contains an popup button)
	/// The latter is the image representation of the cell indicating the marker's name (which simply contains a text field). We need to retrieve the indexes of the corresponding columns.
	NSUInteger nameColIndex = [tableView columnWithIdentifier:@"markerNameColumn"];
	NSUInteger channelColIndex = [tableView columnWithIdentifier:@"markerChannelColumn"];
	if(nameColIndex == NSNotFound || channelColIndex == NSNotFound) {
		return;
	}
	
	/// we make arrays of the components, which we will access later (as the user can drag several markers)
	NSMutableArray *textComponents = [NSMutableArray arrayWithCapacity:rowIndexes.count];		/// the components representing the names of the markers
	NSMutableArray *imageComponents = [NSMutableArray arrayWithCapacity:rowIndexes.count];		/// image components containing the icons for the dyes

	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
		NSTableCellView *cellView  = [tableView viewAtColumn:nameColIndex row:idx makeIfNecessary:YES];
		[textComponents addObject:cellView.draggingImageComponents];
		NSTableCellView* dyeCellView = [tableView viewAtColumn:channelColIndex row:idx makeIfNecessary:YES];
		NSDraggingImageComponent *imageComponent = [NSDraggingImageComponent draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
		if(dyeCellView.imageView) {
			NSImage *dyeImage = dyeCellView.imageView.image;
			if(dyeImage) {
				imageComponent.contents = dyeImage;
				NSSize imageSize = dyeImage.size;
				imageComponent.frame = NSMakeRect(-imageSize.width, 0, imageSize.width, imageSize.height);
			}
		}
		[imageComponents addObject:@[imageComponent]];
	}];
	
	/// we now set the image components of the dragging items
	[session enumerateDraggingItemsWithOptions:NSDraggingItemEnumerationConcurrent
									   forView:tableView
									   classes:@[NSPasteboardItem.class]
								 searchOptions:NSDictionary.new
									usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
		if(idx < textComponents.count) {
			draggingItem.imageComponentsProvider = ^NSArray*(void) {
				return [imageComponents[idx] arrayByAddingObjectsFromArray: textComponents[idx]];
			};
		}
	}];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
	/// when the user drags a row, we copy the underlying marker in the pasteboard
	return [self.tableContent.arrangedObjects objectAtIndex:row];
} 



- (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	NSArray *genotypes = [items valueForKeyPath:@"@unionOfSets.genotypes"];
	if(genotypes.count > 0) {
		return  @"All genotypes at the marker will be removed as well. \nThis action can be undone.";
	}
	
	return [super cautionAlertInformativeStringForItems:items];
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
		[newMarkerPopover showRelativeToRect:button.frame ofView:button.superview preferredEdge:NSRectEdgeMaxY modal:YES];
	}
}

/// Triggered by the "add marker" button on the popover. Adds a marker and save it in the selected panel if it is valid
- (IBAction)addMarker:(id)sender {

	NSError *error;
	/// we add the marker in a background context. We won't save if the marker is not valid.
	NSManagedObjectContext *MOC = ((AppDelegate *)NSApp.delegate).newChildContextOnMainQueue;
	
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

	

	Mmarker *newMarker = [[Mmarker alloc] initWithStart:newMarkerPopover.markerStart end:newMarkerPopover.markerEnd channel:newMarkerPopover.markerChannel panel:panel];
	newMarker.name = newMarkerPopover.markerName;
	newMarker.ploidy = newMarkerPopover.diploid +1; /// Segment 0 represents an haploid marker.
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
	
	BOOL saved = [MOC save:nil];
	if(saved) {
		[self.undoManager setActionName:@"Add Marker"];
		[(AppDelegate *)NSApp.delegate saveAction:self];
	} else {
		error = [NSError errorWithDescription:@"The marker could not be created because an inconsistency in the database." suggestion:@"You may quit the application and try again."];
		[NSApp presentError:error];
	}
	
	[newMarkerPopover close];
	
}



@end
