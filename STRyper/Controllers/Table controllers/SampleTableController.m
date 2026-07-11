//
//  SampleTableController.m
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



#import "SampleTableController.h"
#import "GenotypeTableController.h"
#import "SmartFolder.h"
#import "Chromatogram.h"
#import "FolderListController.h"
#import "SampleSearchHelper.h"
#import "MainWindowController.h"
#import "SizeStandard.h"
#import "FileImporter.h"
#import "SizeStandardTableController.h"
#import "PanelListController.h"
#import "NSManagedObjectContext+NSManagedObjectContextAdditions.h"
#import "PanelFolder.h"
#import "Mmarker.h"
#import "Genotype.h"
#import "Allele.h"
#import "ProgressWindow.h"
#import "IndexImageView.h"
#import "AggregatePredicateEditorRowTemplate.h"

@interface SampleTableController ()

/// Bound to the FolderListController's property of the same name.
@property (nonatomic) __kindof Folder *selectedFolder;


/******** properties used to import ABIF files being dragged from the finder to a folder, ****/
/// They avoid extracting paths of ABIF files at each step of the dragging sequence
/// paths of ABIF files being dragged
@property (nonatomic) NSArray<NSString *> *draggedABIFFilePaths;

/// The identifier of the last dragging sequence (to avoid retrieving the files paths several times for the same sequence)
@property (nonatomic) NSInteger lastDraggingSequence;

/// The image for the button to edit a smart folder, as it is the same button as the one use to filter samples.
@property (nonatomic) NSImage *editSearchImage;

@property (nonatomic) NSDictionary<NSString *, NSString *> *actionNamesForColumnIDs;



@end



@implementation SampleTableController {
	NSDictionary *columnDescription;
}


+ (instancetype)sharedController {
	static SampleTableController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (NSNibName)nibName {
	return @"SamplePane";
}


- (NSArray<NSString *> *)orderedColumnIDs {
	return @[@"sampleNameColumn", @"sampleTypeColumn", @"sampleSizeStandardColumn", @"sizingColumn", @"samplePanelColumn", @"runNameColumn", @"samplePlateColumn",
			 @"sampleWellColumn",@"sampleLaneColumn", @"sampleRunDateColumn", @"sampleFileColumn",  @"sampleImportedDateColumn",
			 @"instrumentColumn", @"protocolColumn",@"getTypeColumn", @"ownerColumn", @"resultsGroupColumn", @"commentColumn"];
}



- (NSDictionary *)columnDescription {
	
	if(!columnDescription) {
		columnDescription = @{
			@"sampleNameColumn": 		@{KeyPathToBind: ChromatogramSampleNameKey, ColumnTitle: @"Name", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Editable sample identifier"},
			@"sampleTypeColumn": 		@{KeyPathToBind: ChromatogramSampleTypeKey, ColumnTitle: @"Sample Type", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Editable type of sample (e.g., negative control, etc.)"},
			@"sampleSizeStandardColumn":@{KeyPathToBind: @"sizeStandard.name", ColumnTitle: @"Size Standard", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Size standard used\n(e.g. Genescan 500)"},
			@"sizingColumn":			@{KeyPathToBind: ChromatogramSizingQualityKey, ColumnTitle: @"Sizing Quality", CellViewID: @"gaugeCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Quality of electrophoresis\nas estimated via the size standard"},
			@"samplePanelColumn": 		@{KeyPathToBind: @"panel.name",ColumnTitle: @"Panel", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Panel of markers analyzed for the sample"},
			@"runNameColumn": 			@{KeyPathToBind: ChromatogramRunNameKey,ColumnTitle: @"Run", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Sequencing run identifier"},
			@"samplePlateColumn": 		@{KeyPathToBind: ChromatogramPlateKey, ColumnTitle: @"Plate", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip: @"Sequencing plate identifier"},
			@"sampleWellColumn": 		@{KeyPathToBind: ChromatogramWellKey,ColumnTitle: @"Well", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Well of the sample in the plate"},
			@"sampleLaneColumn": 		@{KeyPathToBind: ChromatogramLaneKey,ColumnTitle: @"Capillary", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Capillary where the sample migrated"},
			@"sampleRunDateColumn":		@{KeyPathToBind: ChromatogramRunStopTimeKey,ColumnTitle: @"Run Date", CellViewID: @"dateCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Date/time of sequencer run"},
			@"sampleImportedDateColumn":		@{KeyPathToBind: ChromatogramImportDateKey,ColumnTitle: @"Date of Import", CellViewID: @"dateCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Time of import in STRyper"},
			@"sampleFileColumn":		@{KeyPathToBind: ChromatogramSourceFileKey,ColumnTitle: @"Source File", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Path to chromatogram file"},
			@"instrumentColumn":		@{KeyPathToBind: ChromatogramInstrumentKey,ColumnTitle: @"Sequencer", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Model of the sequencer"},
			@"protocolColumn":			@{KeyPathToBind: ChromatogramProtocolKey,ColumnTitle: @"Protocol", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Electrophoresis protocol used"},
			@"getTypeColumn":			@{KeyPathToBind: ChromatogramGelTypeKey,ColumnTitle: @"Gel Type", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip: @"Electrophoresis gel used"},
			@"ownerColumn":			@{KeyPathToBind: ChromatogramOwnerKey,ColumnTitle: @"Owner", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Identifier of the result's owner"},
			@"resultsGroupColumn": @{KeyPathToBind: ChromatogramResultsGroupKey,ColumnTitle: @"Results Group", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES},
			@"commentColumn":			@{KeyPathToBind: ChromatogramCommentKey,ColumnTitle: @"Comment", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Editable comment"},
		};
	}
	return columnDescription;
}


- (NSArrayController *)samples {
	return _arrayController;
}


- (void)setContentSet:(NSSet *)contentSet {
	_contentSet = contentSet.copy;
	if(!_needLoadContent) {
		_needLoadContent = YES;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self _loadContentIfNeeded];
		});
	}
}


- (void)_loadContentIfNeeded {
	if(_needLoadContent) {
		_arrayController.content = self.contentSet;
		_needLoadContent = NO;
	}
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
		_actionNamesForColumnIDs = @{@"sampleNameColumn": @"Rename Sample",
									 @"sampleTypeColumn": @"Edit Sample Type",
									 @"commentColumn": @"Edit Sample Comment"
		};
	}
	return _actionNamesForColumnIDs;
}


- (BOOL)canHideColumn:(NSTableColumn *)column {
	return ![column.identifier isEqualToString: @"sampleNameColumn"];
}


- (void)viewDidLoad {
	
	FolderListController *sharedController = FolderListController.sharedController;
	
	/// we bind buttons that are within our view to relevant keypaths
	for (NSControl *control in self.view.subviews) {
		if([control isKindOfClass:NSControl.class]) {
			if([control isKindOfClass:NSSearchField.class]) {
				NSSearchFieldCell *cell = control.cell;		/// the search field allowing to filter by sample name
				if(cell.searchButtonCell) {
					cell.searchButtonCell.image =[NSImage imageNamed:ACImageNameFilter];
				}
			}
		}
	}
	
	
	[super viewDidLoad];
	
	if(self.samples && sharedController) {
		/// The order of the bindings below may be important to restore the selected samples in `setSelectedFolder:`.
		/// Otherwise the sample table content may not be ready when the selected folder changes.
		[self bind:@"selectedFolder" toObject:sharedController withKeyPath:@"selectedFolder" options:nil];
		
		[self.samples bind:NSFilterPredicateBinding toObject:self withKeyPath:@"selectedFolder.filterPredicate" options:nil];
		[self bind:ContentSetBinding toObject:sharedController withKeyPath:@"selectedFolder.samples" options:nil];
	}
	
	/// We allow dropping files from the Finder to the sample table and panels from the panel outline view
	[self.tableView registerForDraggedTypes: @[NSPasteboardTypeFileURL, PanelDragType, SizeStandardDragType, ChromatogramObjectIDPasteboardType]];
	self.tableView.verticalMotionCanBeginDrag = NO;
	///To convey the notion that a dragged sample changes folder, we use this style:
	//self.tableView.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleGap;
}


- (BOOL) shouldMakeTableHeaderMenu {
	return YES;
}


- (NSString *)entityName {
	return Chromatogram.entity.name;
}


- (NSString *)nameForItem:(id)item {
	return @"Sample";
}


- (NSInteger)itemNameColumn {
	return [self.tableView.tableColumns indexOfObjectPassingTest:^BOOL(NSTableColumn * _Nonnull column, NSUInteger idx, BOOL * _Nonnull stop) {
		return [column.identifier isEqualToString:@"sampleNameColumn"];
	}];
}


- (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	NSArray *genotypes = [items valueForKeyPath:@"@unionOfSets.genotypes"];
	if(genotypes.count > 0) {
		return  @"Associated genotypes will be deleted as well. \nThis can be undone.";
	}
	
	return [super cautionAlertInformativeStringForItems:items];
}


- (BOOL)shouldDeleteObjectsOnRemove {
	return NO;
}

# pragma mark - managing drag & drop of samples (chromatograms)

- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes {
	
	[super tableView:tableView draggingSession:session willBeginAtPoint:screenPoint forRowIndexes:rowIndexes];
	
	/// We hide the dragged rows to convey the notion that samples dragged to another folder will be removed from the table.
	/// We do this "manually" because the dragging style gap appears buggy (doesn't work well when dragging several rows).
	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
		NSTableRowView *rowView = [tableView rowViewAtRow:idx makeIfNecessary:NO];
		rowView.hidden = YES;
	}];
}


- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	[tableView enumerateAvailableRowViewsUsingBlock:^(__kindof NSTableRowView * _Nonnull rowView, NSInteger row) {
		if(rowView.hidden) {
			rowView.hidden = NO;
		}
	}];
}


- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
	
	NSPasteboard *pboard = info.draggingPasteboard;
	if ([pboard.types containsObject:NSPasteboardTypeFileURL] ) {
		/// some files are dragged (from the finder)
		if(!FolderListController.sharedController.canImportSamples) {
			return NSDragOperationNone;
		}
		
		if (!self.samples.canInsert) {
			return NSDragOperationNone;  		/// we only accept samples if a folder is selected
		}
		
		if(self.lastDraggingSequence != info.draggingSequenceNumber) {
			self.lastDraggingSequence = info.draggingSequenceNumber;
			NSArray *fileURLs = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
			self.draggedABIFFilePaths = [FileImporter pathFromURLs:fileURLs conformingToUTTypes:Chromatogram.UTTypes allowChildren:YES];
		}
		
		[tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
		if (self.draggedABIFFilePaths.count > 0) {
			return NSDragOperationCopy;     /// we validate the drop only if at least one ABIF file is dragged
		}
	}
	
	if ([pboard.types containsObject:PanelDragType] || [pboard.types containsObject:SizeStandardDragType]) {
		/// the user drags a panel (folder) or a size standard onto samples. We apply the panel to selected samples
		if(dropOperation == NSTableViewDropAbove) {
			return NSDragOperationNone;
		}
		
		if([self.samples.arrangedObjects count] > 0) {
			[tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
		}
		
		tableView.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleRegular;
		/// We don't show anything special because a panel is not a row to be inserted (I would be better to highlight the selected rows)
		return NSDragOperationCopy;
	}
	
	return NSDragOperationNone;
}



- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
	
	/// For some reason, the drop doesn't trigger a validation of toolbar items, so we force it.
	[NSApp setWindowsNeedUpdate:YES];
	
	NSPasteboard *pboard = info.draggingPasteboard;
	if ([pboard.types containsObject:NSPasteboardTypeFileURL]) {
		if(self.draggedABIFFilePaths.count > 0) {
			SampleFolder *destination = FolderListController.sharedController.selectedFolder;
			if(destination) {
				[self addSamplesFromFiles:self.draggedABIFFilePaths toFolder:destination];
			}
		}
		return YES;
	}
	
	if ([pboard.types containsObject:PanelDragType] ) {
		if([self.samples.arrangedObjects count] == 0) {
			return NO;
		}
		Panel *panel = [self.samples.managedObjectContext objectForURIString:[pboard stringForType:FolderDragType]
															   expectedClass:Panel.class];
		if(!panel) {
			return NO;
		}
		[PanelListController.sharedController applyPanel:panel toSamples:self.samples.arrangedObjects];
		return YES;
	}
	
	if ([pboard.types containsObject:SizeStandardDragType] ) {
		if([self.samples.arrangedObjects count] == 0) {
			return NO;
		}
		SizeStandard *draggedSizeStandard = [self.samples.managedObjectContext objectForURIString:[pboard stringForType:SizeStandardDragType]
																					expectedClass:SizeStandard.class];
		if(!draggedSizeStandard) {
			return NO;
		}
		
		[SizeStandardTableController.sharedController applySizeStandard:draggedSizeStandard toSamples:self.samples.arrangedObjects];
		return YES;
	}
	
	return NO;
}



#pragma mark - managing the table's contextual menu


- (NSArray *)validTargetsOfSender:(id)sender {
	NSArray *targetSamples = [super validTargetsOfSender:sender];
	if([sender action] == @selector(selectGenotypes:)) {
		NSArray *shownGenotypes = GenotypeTableController.sharedController.arrangedObjects;
		NSArray *sampleGenotypes = [targetSamples valueForKeyPath:@"@unionOfSets.genotypes"];
		if(![sampleGenotypes sharesObjectsWithArray:shownGenotypes]) {
			return nil;
		}
	} else if([sender action] == @selector(callGenotypes:) && targetSamples.count > 0) {
		targetSamples = [targetSamples filteredArrayUsingBlock:^BOOL(Chromatogram*  _Nonnull sample, NSUInteger idx) {
			return  sample.sizingQuality.floatValue > 0 && sample.genotypes.count > 0;
		}];
	} else if([sender action] == @selector(showInFinder:) && targetSamples.count > 1) {
		return nil;
	}
	return targetSamples;
}


- (BOOL)validateMenuItem:(NSMenuItem *)item {
	FolderListController *folderListController = FolderListController.sharedController;
	
	if(item.action == @selector(importSamples:)) {
		return folderListController.canImportSamples;
	}
	
	NSArray *targets = [self validTargetsOfSender:item];
	
	if(item.action == @selector(revealInParentFolder:)) {
		if (folderListController.selectedFolder.isSmartFolder) {
			item.hidden = NO;
			NSArray *folders = [targets valueForKeyPath:@"@distinctUnionOfObjects.folder"];
			if(folders.count == 1) {
				item.title = @"Reveal in Parent Folder";
				return YES;
			}
			if(folders.count > 1) {
				item.title = @"(Several parent folders)";
				return NO;
			}
		}
		item.hidden = YES;
		return NO;
	}
	
	if(item.action == @selector(paste:)) {
		return [folderListController validateMenuItem:item];
	}
	
	if([item.identifier isEqualToString:@"pasteOffsets"]) {
		/// We check that at least one target sample has marker for the copied offset(s).
		NSDictionary *dic = Chromatogram.markerOffsetDictionaryFromGeneralPasteBoard;
		if(dic) {
			NSArray *samples = [self validTargetsOfSender:item];
			NSArray *keys = dic.allKeys;
			for(Chromatogram *sample in samples) {
				/// To check if the sample has the right panel, we compare the URIs of its markers to the keys.
				NSArray *URIs = [sample.panel.markers.allObjects valueForKeyPath:@"@unionOfObjects.objectID.URIRepresentation.absoluteString"];
				URIs = [URIs filteredArrayUsingBlock:^BOOL(NSString*  _Nonnull URI, NSUInteger idx) {
					return [keys containsObject:URI];
				}];
				/// Markers may have been deleted since the copy, which is why we didn't just take all URIs that are in the dic.
				if(URIs.count > 0) {
					/// If we're here, the sample must have the right panel. We won't need to inspect other samples.
					NSDictionary *subDic = [dic dictionaryWithValuesForKeys:URIs];
					if(URIs.count > 1) {
						/// If several offsets can be pasted, we prepare a submenu to paste an offset for each marker.
						item.title = @"Paste Marker Offsets";
						NSMenu *menu = NSMenu.new;
						[menu addItemWithTitle:@"All Markers" action:@selector(pasteOffsets:) keyEquivalent:@""];
						menu.itemArray.firstObject.representedObject = subDic;
						menu.identifier = @"markerOffsetSubmenu";
						menu.delegate = self;
						item.submenu = menu;
					} else {
						/// If there is just one offset to paste, there is no need for a submenu.
						item.representedObject = subDic;
						item.title = @"Paste Marker Offset";
						item.submenu = nil;
					}
					item.hidden = NO;
					return YES;
				}
			}
		}
		item.hidden = YES;
		return NO;
	}
	
	return [super validateMenuItem:item];
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	NSArray *targetSamples = [self validTargetsOfSender:menu.itemArray.firstObject];
	if([menu.identifier isEqualToString:@"Standards"]) {
		/// the submenu allowing to apply a size standard to samples.
		/// we determine the size standard of target samples so as to set the state of the equivalent menu item to on (tick-mark).
		NSArray *sizeStandards = [targetSamples valueForKeyPath:@"@distinctUnionOfObjects.sizeStandard"];
		SizeStandard *currentStandard = nil;
		if(sizeStandards.count == 1) {
			currentStandard = sizeStandards.firstObject;
		}
		[menu removeAllItems];
		for(SizeStandard *standard in SizeStandardTableController.sharedController.arrangedObjects) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:standard.name action:@selector(applySizeStandard:) keyEquivalent:@""];
			item.target = self;
			item.representedObject = standard;
			[menu addItem:item];
			if(standard == currentStandard) {
				item.state = NSControlStateValueOn;
			}
		}
		
		return;
	}
	
	if(menu == self.tableView.menu) {
		for (NSMenuItem *item in menu.itemArray) {
			if([item.identifier isEqualToString:@"Panels"]) {
				/// we populate the menu allowing to apply a panel with available panels.
				/// We do it by providing a new menu to the parent item rather than updating the menu itself (by adding items),
				NSMenu *panelMenu = [PanelListController.sharedController menuForPanelsWithTarget:self fontSize:menu.font.pointSize];
				if (panelMenu.itemArray.count > 0) {
					item.hidden = NO;
					item.submenu = panelMenu;	/// we populate it with a hierarchical menu representing the available panels within folders
				} else {
					item.hidden = YES;
				}
			}
		}
	}
	
	if ([menu.identifier isEqualToString:@"fittingMethod"]) {
		/// we add a tick-mark to the menu item corresponding to the fitting method currently applied to the target sample(s)
		for(NSMenuItem *item in menu.itemArray) {
			item.state = NSControlStateValueOff;
		}
		NSArray *fittingMethods = [targetSamples valueForKeyPath:@"@distinctUnionOfObjects.polynomialOrder"];
		fittingMethods  = [fittingMethods sortedArrayUsingSelector:@selector(compare:)];
		if(fittingMethods.count > 2 || (fittingMethods.count > 1 && ![fittingMethods containsObject:@(-1)])) {
			/// if the target samples have different fitting method, or if no fitting method is applied, we can return
			return;
		}
		int order = [fittingMethods.lastObject intValue];
		if(order < 0 || order > menu.itemArray.count) {
			return;
		}
		NSMenuItem *item = menu.itemArray[order];
		item.state = NSControlStateValueOn;
	}
	
	if([menu.identifier isEqualToString: @"markerOffsetSubmenu"]) {
		/// The menu that allows pasting the offset of the desired marker.
		if(menu.numberOfItems > 1 || menu.numberOfItems == 0) {
			/// If there are several items, the menu has already been updated.
			/// `validateMenuItem:` creates a new submenu with one item when appropriate.
			return;
		}
		/// The first item should represent the dictionary for all valid copied marker offsets.
		NSDictionary *dic = menu.itemArray.firstObject.representedObject;
		if(![dic isKindOfClass:NSDictionary.class] || dic.count < 1) {
			return;
		}
		
		NSArray *URIs = dic.allKeys;
		/// We create a menu item for each marker,  using the marker name.
		/// We add markers to an array, as we will sort them by name to create the submenu.
		NSMutableArray *markers = [NSMutableArray arrayWithCapacity:URIs.count];
		NSManagedObjectContext *MOC = self.samples.managedObjectContext;
		for(NSString *URI in URIs) {
			Mmarker *marker = [MOC objectForURIString:URI expectedClass:Mmarker.class];
			if(marker) {
				[markers addObject:marker];
			}
		}
		if(markers.count > 0) {
			NSArray *sortedMarkers = [markers sortedArrayUsingKey:@"name" ascending:YES];
			/// To help the user, we represent the channel of each marker by an image.
			NSArray *channelColorImages = MarkerTableController.channelColorImages;
			for(Mmarker *marker in sortedMarkers) {
				NSMenuItem *item = NSMenuItem.new;
				item.title = marker.name;
				if(marker.channel < channelColorImages.count) {
					item.image = channelColorImages[marker.channel];
				}
				item.action = @selector(pasteOffsets:);
				item.target = self;
				NSString *URI = marker.objectID.URIRepresentation.absoluteString;
				if(URI) {
					item.representedObject = [dic dictionaryWithValuesForKeys:@[URI]];
					[menu addItem:item];
				}
			}
		}
	}
	
	[super menuNeedsUpdate:menu];
}



#pragma mark - user actions on samples

- (BOOL)selectAndShowObjects:(NSArray *)objects {
	BOOL success = [super selectObjects:objects];
	MainWindowController.sharedController.sourceController = self;
	return success;
}

/// Applies a size standard (inferred from the sender) to target samples.
- (IBAction)applySizeStandard:(id)sender {
	SizeStandard *standard;
	if([sender class] == NSMenuItem.class) {
		standard = [sender representedObject];
	} else {
		standard = SizeStandardTableController.sharedController.selectedObjects.firstObject;
	}
	if(!standard) {
		return;
	}
	[SizeStandardTableController.sharedController applySizeStandard:standard toSamples:[self validTargetsOfSender:sender]];
}



/// Applies a fitting method (inferred from the sender) to target samples.
- (IBAction)applyFittingMethod:(NSMenuItem *)sender {
	int order = (int)sender.tag;
	if(order < 0) {
		order = 0;
	}
	if(order > 2) {
		order = 2;
	}
	[self.undoManager setActionName:@"Apply Fitting Method"];
	for(Chromatogram *sample in [self validTargetsOfSender:sender]) {
		sample.polynomialOrder = order;
	}
	[AppDelegate.sharedInstance saveAction:self];
}


/// Applies a panel (inferred from the sender) to target samples.
- (IBAction)applyPanel:(id)sender {
	PanelListController *panelListController = PanelListController.sharedController;
	Panel *panel;
	if([sender class] == NSMenuItem.class) {
		panel = [sender representedObject];
	} else {
		panel = (Panel *)panelListController.selectedFolder;
	}
	if(![panel isKindOfClass:Panel.class] || !panel.isPanel) {
		return;
	}
	[panelListController applyPanel:panel toSamples: [self validTargetsOfSender:sender]];
	
}


- (IBAction)callGenotypes:(id)sender {
	BOOL annotateSuppPeaks = [NSUserDefaults.standardUserDefaults boolForKey:AnnotateAdditionalPeaks];
	
	NSArray *samples =[self validTargetsOfSender:sender];
	[self.undoManager setActionName:@"Call Genotypes"];
	for(Chromatogram *sample in samples) {
		for (Genotype *genotype in sample.genotypes) {
			[genotype callAllelesAndAdditionalPeak:annotateSuppPeaks];
		}
	}
	[AppDelegate.sharedInstance saveAction:self];
	
}


/// Selects the genotypes associated with target samples
- (IBAction)selectGenotypes:(id)sender {
	NSArray *genotypes = [[self validTargetsOfSender:sender] valueForKeyPath:@"@unionOfSets.genotypes"];
	
	GenotypeTableController *genotypeTableController = GenotypeTableController.sharedController;
	[genotypeTableController selectAndShowObjects:genotypes];
}


- (IBAction) revealInParentFolder:(id)sender {
	/// if we show the contents of a smart folder, this allows selecting the parent folder of clicked samples, only if they all belong to the same folder
	NSArray *targetSamples = [self validTargetsOfSender:sender];
	NSArray *folders = [targetSamples valueForKeyPath:@"@distinctUnionOfObjects.folder"];
	if(folders.count != 1) {
		return;
	}
	Folder *folder = folders.firstObject;
	if([FolderListController.sharedController selectFolder:folder]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self selectAndShowObjects:targetSamples];
		});
		
	}
}


/// puts target samples into the trash folder (which is emptied when the application quits)
- (void)deleteItems:(NSArray *)items {

	NSSet *samples = [NSSet setWithArray:items];
	[FolderListController.sharedController.trashFolder addSamples:samples];
	[AppDelegate.sharedInstance saveAction:self];
}


-(IBAction)showInFinder:(id)sender {
	NSArray<Chromatogram *> *targetSamples = [self validTargetsOfSender:sender];
	if(targetSamples.count == 1 && [targetSamples.firstObject respondsToSelector:@selector(sourceFile)]) {
		NSString *path = targetSamples.firstObject.sourceFile;
		if(path) {
			BOOL reachable = [NSWorkspace.sharedWorkspace selectFile:path inFileViewerRootedAtPath:@""];
			if(!reachable) {
				NSError *error = [NSError errorWithDescription:@"Source file not found."
													suggestion: @"The file may have been moved or deleted since it was imported."];
				[NSApp presentError:error];
			}
		}
	}
}

#pragma mark - importing samples

/// imports samples into the selected folder
- (void)importSamples:(id)sender {
	if(FileImporter.sharedFileImporter.importOnGoing) {
		return;
	}
	
	NSWindow *window = self.view.window;
	if(!window) {
		return;
	}
	
	FolderListController *folderListController = FolderListController.sharedController;
	
	if(folderListController.rootFolder.subfolders.count == 0) {
		/// if there is no folder, we propose to create one
		NSAlert *alert = NSAlert.new;
		alert.messageText = @"There is no folder to import samples into.";
		[alert addButtonWithTitle:@"New Folder"];
		[alert addButtonWithTitle:@"Cancel"];
		
		[alert beginSheetModalForWindow: window completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn) {
				[folderListController addFolder:self];
			}
		}];
		return;
	}
	
	SampleFolder *selectedFolder = [folderListController _targetFolderOfSender: sender];
	if(!selectedFolder) {
		selectedFolder = folderListController.selectedFolder;
	}
	
	if(!selectedFolder) {
		NSAlert *alert = NSAlert.new;
		alert.messageText = @"There is no selected folder to import samples into.";
		alert.informativeText = @"Please select a folder from the sidebar.";
		[alert addButtonWithTitle:@"Ok"];
		[alert beginSheetModalForWindow: window completionHandler:^(NSModalResponse returnCode) {
			[folderListController showLeftPane];
		}];
		return;
	}
	
	if(selectedFolder.isSmartFolder) {
		NSAlert *alert = NSAlert.new;
		alert.messageText = @"The selected folder is a smart folder. You cannot import samples into it.";
		alert.informativeText = @"Please select a folder in the sidebar.";
		[alert addButtonWithTitle:@"Ok"];
		[alert beginSheetModalForWindow: window completionHandler:^(NSModalResponse returnCode) {
			[folderListController showLeftPane];
		}];
		return;
	}
	
	
	NSOpenPanel* panel = NSOpenPanel.openPanel;
	panel.prompt = @"Import";
	panel.canChooseDirectories = YES;
	panel.allowsMultipleSelection = YES;
	panel.delegate = self;
	panel.message = [NSString stringWithFormat: @"Select chromatogram files to import into folder '%@'.", selectedFolder.name];
	panel.allowedFileTypes = Chromatogram.UTTypes.allObjects;
	[panel beginSheetModalForWindow:window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSArray *filePaths = [FileImporter pathFromURLs:panel.URLs conformingToUTTypes:Chromatogram.UTTypes allowChildren:YES];
			[self addSamplesFromFiles:filePaths toFolder:selectedFolder];
		}
	}];
}


- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
	/// We allow selecting files and folder containing valid files or subfolders
	return YES; //[FileImporter isValidURL:url forPanel:sender browsing:YES]; // disabled as it may be disturbing to the user.
}



- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError *__autoreleasing  _Nullable *)outError {
	NSOpenPanel* panel = (NSOpenPanel *)sender;
	for(NSURL *url in panel.URLs) {
		if([FileImporter isValidURL:url forPanel:sender browsing:NO]) {
			return YES;
		}
	}

	if(outError != NULL) {
		*outError = [NSError errorWithDescription:@"The selection does not contain chromatogram files." suggestion:@""];
	}
	return NO;
}




-(void) addSamplesFromFiles:(NSArray <NSString *>*)filePaths toFolder:(SampleFolder *)folder {
	NSManagedObjectContext *MOC = folder.managedObjectContext;
	CDUndoManager *undoManager = (CDUndoManager *)MOC.undoManager;
	[MOC processPendingChanges];
	[undoManager disableUndoRegistration];
	NSMutableSet *importedSamples = NSMutableSet.new;
	BOOL applySizeStandard = [NSUserDefaults.standardUserDefaults boolForKey:AutoDetectSizeStandard];
	
	ProgressWindow *progressWindow = ProgressWindow.new;
	NSProgress *importProgress = NSProgress.new;
	[progressWindow showProgressWindowForProgress:importProgress afterDelay:1.0 modal:YES parentWindow:self.view.window];
	[FileImporter.sharedFileImporter importSamplesFromFiles:filePaths
												  batchSize:100
												   progress:importProgress
										intermediateHandler:^BOOL(NSManagedObjectID *containerFolderID) {
		if(folder.isDeleted || !folder.managedObjectContext) {
			return NO;
		}
		__block BOOL success = YES;
		/// We retrieved the imported samples in the view context, to add them to the folder (hence the sample table, if the folder is selected).
		[MOC performBlockAndWait:^{  /// The  intermediateHandler must return only after the containing folder is retrieved
			SampleFolder *scratchFolder = [MOC existingObjectWithID:containerFolderID error:nil];
			if(scratchFolder) {
				[MOC performBlock:^{
					/// We can update the table and apply size standards asynchronously.
					NSSet *samplesInBatch = scratchFolder.samples;
					if(samplesInBatch.count > 0) {
						[importedSamples unionSet:samplesInBatch];
						for(Chromatogram *sample in samplesInBatch) {
							if(applySizeStandard) {
								SizeStandard *sizeStandard = [SizeStandardTableController.sharedController sizeStandardForName:sample.standardName];
								if(sizeStandard && sizeStandard.managedObjectContext != MOC) {
									sizeStandard = [MOC existingObjectWithID:sizeStandard.objectID error:nil];
								}
								if(sizeStandard) {
									[sizeStandard sizeSample:sample];
								}
							}
							if(!sample.sizeStandard) {
								/// if we don't apply a size standard, we make the sample compute default sizing coefficients
								[sample setLinearCoefsForReadLength:DefaultReadLength];
							}
						}
						[folder addSamples:samplesInBatch];
					}
					[MOC deleteObject:scratchFolder];
				}];
			} else {
				success = NO;
			}
		}];
		return success;
	}
										  completionHandler:^(NSError *error) {
		[progressWindow stopShowingProgressAndClose];
		NSInteger sampleCount = importedSamples.count;
		if(error) {
			if(error.code == NSUserCancelledError && sampleCount > 0) {
				NSString *description = [NSString stringWithFormat:@"The import was cancelled after %ld samples have been imported.", sampleCount];
				error = [NSError cancelOperationErrorWithDescription:description suggestion:@"You can undo to remove these samples."];
				/// It is essentially impossible that the user cancels after importing just 1 sample, so we don't bother with plurals.
			}
			[MainWindowController.sharedController showAlertForError:error];
		}
		
		[undoManager enableUndoRegistration];
		if(sampleCount > 0) {
			NSString *actionName = importedSamples.count > 1? @"Import Samples" : @"Import Sample";
			if([undoManager respondsToSelector:@selector(forceActionName:)]) {
				[undoManager forceActionName:actionName];
			} else {
				[undoManager setActionName:actionName];
			}
			[undoManager registerUndoWithTarget:self selector:@selector(deleteItems:) object:importedSamples.allObjects];
			
			[NSApp setWindowsNeedUpdate:YES]; /// Because the undo/redo buttons don't update immediately.
			
			/// We show imported samples on the viewer.
			[FolderListController.sharedController selectFolder:folder];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self selectAndShowObjects:importedSamples.allObjects];
			});

			if(folder == self.selectedFolder && folder.filterPredicate) {
				NSSet *filteredSamples = [importedSamples filteredSetUsingPredicate:folder.filterPredicate];
				NSInteger filtered = sampleCount - filteredSamples.count;
				if(filtered > 0) {
					NSString *errorText = filtered == 1? @"One imported sample is masked by the filter applied to the selected folder." :
					[NSString stringWithFormat: @"%ld imported samples are masked by the filter applied to the selected folder.", filtered];
					NSError *error = [NSError errorWithDescription:errorText suggestion:@"You may remove the filter."];
					NSAlert *alert = [NSAlert alertWithError:error];
					[alert addButtonWithTitle:@"Leave Filter"];
					[alert addButtonWithTitle:@"Remove Filter"];
					[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
						if(returnCode == NSAlertSecondButtonReturn) {
							folder.filterPredicate = nil;
						}
					}];
				}
			}
		}
	}];
}



- (void)copyItems:(NSArray *)items ToPasteBoard:(NSPasteboard *)pasteboard {
	[super copyItems:items ToPasteBoard:pasteboard];
	
	/// We write a combined string containing the object IDs of selected elements.
	/// Using a single pasteboard item is much faster than using one per copied element, when we paste.
	[self.samples.managedObjectContext obtainPermanentIDsForObjects:items error:nil];
	NSArray *URIStrings = [items valueForKeyPath:@"@unionOfObjects.objectID.URIRepresentation.absoluteString"];
	NSString *concat = [URIStrings componentsJoinedByString:@"\n"];
	[pasteboard setString:concat forType:ChromatogramCombinedPasteboardType];
	
	if(items.count == 1) {
		/// If only one sample is copied, we write it to the pasteboard, which copies its marker offsets (if any).
		Chromatogram *sample = items.firstObject;
		NSSet *genotypes = sample.genotypes;
		if(genotypes.count > 0) {
			[pasteboard writeObjects: @[sample]];
		}
	}
}


-(IBAction)paste:(id)sender {
	FolderListController *sharedController = FolderListController.sharedController;
	if(!sharedController.canImportSamples) {
		/// There may be no valid selected folder to paste sample into, in which case we do nothing.
		return;
	}
	[self copySamplesFromPasteboard:NSPasteboard.generalPasteboard toFolder:sharedController.selectedFolder];
}


- (void)copySamplesFromPasteboard:(NSPasteboard *)pboard toFolder:(SampleFolder *)folder {
	NSArray *items;
	if([pboard.types containsObject:ChromatogramCombinedPasteboardType]) {
		NSString *string = [pboard stringForType:ChromatogramCombinedPasteboardType];
		items = [string componentsSeparatedByString:@"\n"];
	} else if([pboard.types containsObject:ChromatogramObjectIDPasteboardType]) {
		items = pboard.pasteboardItems;
	} else {
		return;
	}
	
	/// Undoing the copy (hence creation) of chromatograms may cause crashes on some macOS versions.
	/// This may have been fixed, but to avoid any risk, we disable undo. The undo action will move pasted samples to the trash.
	CDUndoManager *undoManager = (CDUndoManager *)self.undoManager;
	[undoManager disableUndoRegistration];
	NSInteger __block copiedCount = 0;
	[self pasteSamplesFromItems:items completionHandler:^(NSError *error, SampleFolder *scratchFolder) {
		/// to transfer pasted samples to the table, we need to materialize the folder in our context.
		/// It won't appear in the folder list, as this scratch folder has no parent.
		
		scratchFolder = [self.samples.managedObjectContext existingObjectWithID:scratchFolder.objectID error:nil];
		NSSet *copiedSamples = scratchFolder.samples.copy;
		copiedCount = copiedSamples.count;
		if(copiedCount > 0) {
			[folder addSamples:copiedSamples];
			[scratchFolder.managedObjectContext deleteObject:scratchFolder];
			[AppDelegate.sharedInstance saveAction:nil];

			[undoManager enableUndoRegistration];
			NSString *action = copiedCount > 1? @"Paste Samples" : @"Paste Sample";
			if([pboard.name isEqualToString:NSPasteboardNameDrag]) {
				action = copiedCount > 1? @"Copy Samples" : @"Copy Sample";
			}
			[undoManager forceActionName:action];
			[undoManager registerUndoWithTarget:self selector:@selector(deleteItems:) object:copiedSamples.allObjects];
			
			[FolderListController.sharedController selectFolder:folder];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self selectObjects:copiedSamples.allObjects];
			});
			
		} else {
			[undoManager enableUndoRegistration];
		}
		
		if(error && error.code != NSUserCancelledError) {
			/// we did not manage the error first, as the operation above may block the UI (hence the dismissal of any error alert) if many samples are imported
			[MainWindowController.sharedController showAlertForError:error];
		}
	}];
	
}


- (IBAction)pasteOffsets:(NSMenuItem *)sender {
	NSArray *targetSamples = [self validTargetsOfSender:sender];
	if(targetSamples.count < 1) {
		return;
	}
	
	NSDictionary *dic = sender.representedObject;
	if(![dic isKindOfClass:NSDictionary.class]) {
		return;
	}
	
	BOOL pasted = NO;
	for(Chromatogram *sample in targetSamples) {
		for(Genotype *genotype in sample.genotypes) {
			NSString *URI = genotype.marker.objectID.URIRepresentation.absoluteString;
			NSData *offsetData = dic[URI];
			if([offsetData isKindOfClass:NSData.class] && offsetData.length == sizeof(MarkerOffset)) {
				genotype.offsetData = offsetData;
				pasted = YES;
			}
		}
	}
	
	if(pasted) {
		[self.undoManager setActionName:@"Paste Marker Offset(s)"];
	}
}


/// Retrieves copied sample from pasteboard items and places them in a folder materialized in a background context
///
/// The operation occurs in the background and the method spawns a progress window that shows the progress and allows cancellation.
/// - Parameters:
///   - items: The pasteboard items that represent chromatogram objects to be pasted. The array can be composed of `NSPasteboardItem` objects with a `ChromatogramPasteboardType` or of `NSString` objects representing the URI of the chromatogram object IDs.
///   - callbackBlock: A block that is called at the end of the operation. On output, its `NSError` argument contains any error that has occurred.
///   Its `SampleFolder` argument is a newly created ``SampleFolder`` (with no ``Folder/parent``) that contains all copied ``SampleFolder/samples``. This folder is materialized in a ``AppDelegate/newChildContext``.
- (void)pasteSamplesFromItems:(NSArray*) items completionHandler: (void (^)(NSError *error, SampleFolder *folder))callbackBlock {
	NSOperationQueue *callingQueue = NSOperationQueue.currentQueue;
	NSUInteger nSamples = items.count;
	NSInteger batchSize = nSamples/100 +1;
	ProgressWindow *progressWindow = ProgressWindow.new;
	NSWindow *window = self.tableView.window;
	NSManagedObjectContext *MOC = ((AppDelegate*)NSApp.delegate).newChildContext;
	[MOC performBlock:^{
		NSError *error;
		NSMutableArray *copyErrors = NSMutableArray.new;
		SampleFolder *folder = [[SampleFolder alloc] initWithContext:MOC];
		[MOC obtainPermanentIDsForObjects:@[folder] error:nil];
		[folder autoName]; /// To avoid a validation error.
		
		NSProgress *pasteProgress = [NSProgress progressWithTotalUnitCount:nSamples];
		[progressWindow showProgressWindowForProgress:pasteProgress afterDelay:1.0 modal:YES parentWindow:window];
		[pasteProgress becomeCurrentWithPendingUnitCount:1];
		
		NSUInteger numberOfCopiedSamples = 0;
		for (id item in items) {
			if(pasteProgress.isCancelled) {
				break;
			}
			@autoreleasepool {
				NSError *copyError;
				numberOfCopiedSamples++;
				
				NSString *URIString;
				if([item isKindOfClass:NSPasteboardItem.class]) {
					URIString = [item stringForType:ChromatogramObjectIDPasteboardType];
					if(!URIString) {
						continue;
					}
				} else if([item isKindOfClass:NSString.class]) {
					URIString = item;
				} else {
					continue;
				}
				
				Chromatogram *copiedSample;
				Chromatogram *sample = [MOC objectForURIString:URIString expectedClass:Chromatogram.class];
				if(!sample.isDeleted && [sample validateForUpdate:nil]) {
					copiedSample = sample.copy;
					copiedSample.folder = folder;
				} else {
					NSString *ID = sample.sampleName? sample.sampleName : URIString;
					copyError = [NSError errorWithDescription:[NSString stringWithFormat:@"Sample %@ could not be pasted.", ID]
												   suggestion:@""];
				}
				
				if(numberOfCopiedSamples % batchSize == 0) {
					pasteProgress.completedUnitCount = numberOfCopiedSamples;
					pasteProgress.localizedDescription = [NSString stringWithFormat:@"%ld of %ld samples pasted",
														  numberOfCopiedSamples, nSamples];
				}
				
				if(copyError) {
					[copyErrors addObject:copyError];
					if(copiedSample) {
						/// in case a Chromatogram object was created, we delete it (though none should be returned if there is an error)
						[copiedSample.managedObjectContext deleteObject:sample];
					}
				}
			}
		}
		
		[pasteProgress resignCurrent];
		
		if(pasteProgress.isCancelled) {
			error = [NSError cancelOperationErrorWithDescription:@"The user cancelled the operation." suggestion:@""];
		} else if(folder.samples.count > 0 && folder.managedObjectContext.hasChanges) {
			pasteProgress.localizedDescription = @"Saving copied samples…";
			pasteProgress.cancellable = NO;
			[folder.managedObjectContext save:&error];
			
			if(error) {
				error = [error errorWithNewDescription:@"The sample(s) could not be pasted because an error occurred saving the database."
										   suggestion:@"Some sample(s) may contain invalid data."];
				/// hopefully, this kind of error will not happen if the checks made were rigorous enough.
			}
		}
		
		if(!error && copyErrors.count >0) {
			if(copyErrors.count == 1) {
				error = copyErrors.firstObject;		/// if there was just one problematic sample, the error we report is the one associated with this file
			} else {								/// else we indicate the number of failures and include the errors in the user info dictionary
				NSString *description = [NSString stringWithFormat:@"%ld sample(s) could not be pasted.", copyErrors.count];
				error = [NSError errorWithDomain:STRyperErrorDomain
											code:NSValidationErrorMinimum
										userInfo:@{NSDetailedErrorsKey: copyErrors.copy,
												   NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
												   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"See the error log for details.", nil)
												 }];
			}
		}
		
		[callingQueue addOperationWithBlock:^{
			callbackBlock(error, folder);
		}];
		
		[progressWindow stopShowingProgressAndClose];
	}];
}


NSPasteboardType _Nonnull const ChromatogramCombinedPasteboardType = @"org.jpeccoud.stryper.chromatogramCombinedPasteboardType";


#pragma mark - filtering


- (NSImage *)filterButtonImage {
	if(self.selectedFolder.isSmartFolder) {
		return self.editSearchImage;
	}
	return super.filterButtonImage;
}


- (NSImage *)editSearchImage {
	if(!_editSearchImage) {
		_editSearchImage = [NSImage imageNamed:ACImageNameEditSearch];
	}
	return _editSearchImage;
}


- (void)filterButtonAction:(NSButton *)sender {
	if(self.selectedFolder.isSmartFolder) {
		[FolderListController.sharedController editSmartFolder:sender];
	} else {
		[super filterButtonAction:sender];
	}
}


- (void)configurePredicateEditor:(NSPredicateEditor *)predicateEditor {
	
	/// The searchable attributes are those shown in the sample table.
	NSDictionary *columnDescription = self.columnDescription;
	/// We also use the column ids to show searchable attributes in a consistent order
	NSArray *sampleColumnIDs = self.orderedColumnIDs;
	if(!columnDescription || !sampleColumnIDs) {
		return;
	}
	
	/// we prepare the keyPaths (attributes) that the predicate editor will allow searching. sampleName is not in sampleColumnIDs
	NSMutableArray *keyPaths = [NSMutableArray arrayWithObject:ChromatogramSampleNameKey];
	/// We also prepare the titles for the menu items of the editor left popup buttons, as keypath names are not user-friendly
	NSMutableArray *titles = [NSMutableArray arrayWithObject:@"Sample Name"];
	
	if(predicateEditor.window == (NSWindow *)SampleSearchHelper.sharedHelper.searchWindow) {
		/// For the predicate of the search window, we allow searching by folder name.
		/// This does not make sense in the predicate editor that filters the content of the selected folder.
		[keyPaths addObject:@"folder.name"];
		[titles addObject:@"Folder Name"];
	}
	
	NSDictionary<NSString *, NSString*> *titlesForKeyPaths = @{@"panel.name": @"Panel Name",
															   ChromatogramPlateKey: @"Plate Name",
															   ChromatogramRunNameKey: @"Run Name"};
	
	NSArray *columnDescriptions = [columnDescription objectsForKeys:sampleColumnIDs notFoundMarker:@""];		/// Dictionaries describing the sample-related columns
	for(NSDictionary *colDescription in columnDescriptions) {
		NSString *keyPath = colDescription[KeyPathToBind];
		if(keyPath) {
			NSString *title = titlesForKeyPaths[keyPath];
			if(!title) {
				title = colDescription[ColumnTitle];
			}
			if(title) {
				[keyPaths addObject:keyPath];
				[titles addObject:title];
			}
		}
	}
	
	NSArray<NSPredicateEditorRowTemplate *> *rowTemplates = [AggregatePredicateEditorRowTemplate templatesWithAttributeKeyPaths:keyPaths inEntityDescription:Chromatogram.entity];
		
	/// We add a template to find samples by marker name, because it uses a different modifier.
	/// A template for this keypath could be generated with `templatesWithAttributeKeyPaths`, but it would use the direct comparison modifier.
	NSMutableArray *finalTemplates = rowTemplates.mutableCopy;
	NSString *markerNameKeyPath = @"panel.markers.name";
	[keyPaths addObject:markerNameKeyPath];
	[titles addObject:@"Marker Name"];
	NSPredicateEditorRowTemplate *markerNameTemplate = [[NSPredicateEditorRowTemplate alloc]
														initWithLeftExpressions:@[[NSExpression expressionForKeyPath:markerNameKeyPath]]
														rightExpressionAttributeType:NSStringAttributeType
														modifier:NSAnyPredicateModifier
														operators:rowTemplates.firstObject.operators
														options:0];
	[finalTemplates insertObject:markerNameTemplate atIndex:2];
	/// The index of 2 was determined by trial and error, so that "Marker Name" appears at an appropriate position in the menu.
	
	NSArray *compoundTypes = @[@(NSNotPredicateType), @(NSAndPredicateType),  @(NSOrPredicateType)];
	NSPredicateEditorRowTemplate *compound = [[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:compoundTypes];
	
	/// The predicate editor has a compound predicate row template created in IB, we keep it
	predicateEditor.rowTemplates = [@[compound] arrayByAddingObjectsFromArray:finalTemplates];
	
	
	/// We create a formatting dictionary to translate attribute names into menu item titles. We don't translate other fields (operators)
	NSMutableArray *keys = NSMutableArray.new;		/// the future keys of the dictionary
	for(NSString *keyPath in keyPaths) {
		NSString *key = [NSString stringWithFormat: @"%@%@%@",  @"%[", keyPath, @"]@ %@ %@"];		/// see https://funwithobjc.tumblr.com/post/1482915398/localizing-nspredicateeditor
		[keys addObject:key];
	}
	
	NSMutableArray *values = NSMutableArray.new;	/// the future values
	for(NSString *title in titles) {
		NSString *value = [NSString stringWithFormat: @"%@%@%@",  @"%1$[", title, @"]@ %2$@ %3$@"];
		[values addObject:value];
	}
	
	predicateEditor.formattingDictionary = [NSDictionary dictionaryWithObjects:values forKeys:keys];
}


- (NSPredicate *)defaultFilterPredicate {
	return [NSPredicate predicateWithFormat: @"(%K CONTAINS[c] '' )", ChromatogramSampleNameKey];
}


- (void)applyFilterPredicate:(NSPredicate *)filterPredicate {
	CDUndoManager *undoManager = (CDUndoManager*)self.undoManager;
	NSString *actionName = filterPredicate == nil ? @"Remove Filter on Samples" : @"Apply Filter on Samples";
	[undoManager forceActionName:actionName];

	[self setFilterPredicate:filterPredicate forFolder:self.selectedFolder];
}


-(void)setFilterPredicate:(NSPredicate *)filterPredicate forFolder:(Folder *)folder {
	NSPredicate *previousPredicate = folder.filterPredicate;
	if(previousPredicate == filterPredicate && folder == self.selectedFolder) {
		[self.samples rearrangeObjects];
	}
	folder.filterPredicate = filterPredicate;
	[self.undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
		[self setFilterPredicate:previousPredicate forFolder:folder];
	}];
}

#pragma mark - recording and restoring sample selection



- (void)setSelectedFolder:(__kindof Folder *)selectedFolder {
	_selectedFolder = selectedFolder;

	NSButton *filterButton = self.filterButton;
	if(selectedFolder.isSmartFolder) {
		filterButton.toolTip = @"Edit smart folder";
		filterButton.image = self.editSearchImage;
	} else {
		filterButton.toolTip = @"Filter samples";
		filterButton.image = super.filterButtonImage;
	}
}



@end
