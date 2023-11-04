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
#import "Genotype.h"
#import "ProgressWindow.h"

@interface SampleTableController ()

@property (nonatomic) NSArray <Chromatogram *> *draggedSamples; /// redefinition of the readonly property as readwrite

/******** properties used to import ABIF files being dragged from the finder to a folder, ****/
/// They avoid extracting paths of ABIF files at each step of the dragging sequence
/// paths of ABIF files being dragged
@property (nonatomic) NSArray *draggedABIFFilePaths;

/// The identifier of the last dragging sequence (to avoid retrieving the files paths several times for the same sequence)
@property (nonatomic) NSInteger lastDraggingSequence;

@end


@implementation SampleTableController {
	NSDictionary *columnDescription;
}

+ (instancetype)sharedController {
	static SampleTableController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = [[self alloc] init];
	});
	return controller;
}


- (instancetype)init {
	self = [super initWithNibName:@"SamplePane" bundle:nil];
	return self;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	/// "sampleName" is not included as it is already in the xib (this column contains the prototypes for the table cell views)
	return @[@"sampleTypeColumn", @"sampleSizeStandardColumn", @"sizingColumn", @"samplePanelColumn", @"runNameColumn", @"samplePlateColumn",
			 @"sampleWellColumn",@"sampleLaneColumn", @"sampleRunDateColumn", @"sampleFileColumn",  @"sampleImportedDateColumn",
			 @"instrumentColumn", @"protocolColumn",@"getTypeColumn", @"ownerColumn", @"resultsGroupColumn", @"commentColumn"];
}



- (NSDictionary *)columnDescription {
	
	if(!columnDescription) {
		columnDescription = @{
			@"sampleNameColumn": 		@{KeyPathToBind: ChromatogramSampleNameKey, ColumnTitle: @"Name", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES},
			@"sampleTypeColumn": 		@{KeyPathToBind: ChromatogramSampleTypeKey, ColumnTitle: @"Sample Type", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES},
			@"sampleSizeStandardColumn":@{KeyPathToBind: @"sizeStandard.name", ColumnTitle: @"Size Standard", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			
			@"sizingColumn":			@{KeyPathToBind: ChromatogramSizingQualityKey, ColumnTitle: @"Sizing Quality", CellViewID: @"gaugeCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"samplePanelColumn": 		@{KeyPathToBind: @"panel.name",ColumnTitle: @"Panel", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"runNameColumn": 			@{KeyPathToBind: ChromatogramRunNameKey,ColumnTitle: @"Run", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"samplePlateColumn": 		@{KeyPathToBind: ChromatogramPlateKey, ColumnTitle: @"Plate", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"sampleWellColumn": 		@{KeyPathToBind: ChromatogramWellKey,ColumnTitle: @"Well", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"sampleLaneColumn": 		@{KeyPathToBind: ChromatogramLaneKey,ColumnTitle: @"Capillary", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"sampleRunDateColumn":		@{KeyPathToBind: ChromatogramRunStopTimeKey,ColumnTitle: @"Run Date", CellViewID: @"dateCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"sampleImportedDateColumn":		@{KeyPathToBind: ChromatogramImportDateKey,ColumnTitle: @"Date of Import", CellViewID: @"dateCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"sampleFileColumn":		@{KeyPathToBind: ChromatogramSourceFileKey,ColumnTitle: @"Source File", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"instrumentColumn":		@{KeyPathToBind: ChromatogramInstrumentKey,ColumnTitle: @"Instrument", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"protocolColumn":			@{KeyPathToBind: ChromatogramProtocolKey,ColumnTitle: @"Protocol", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"getTypeColumn":			@{KeyPathToBind: ChromatogramGelTypeKey,ColumnTitle: @"Gel Type", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"ownerColumn":			@{KeyPathToBind: ChromatogramOwnerKey,ColumnTitle: @"Owner", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"resultsGroupColumn":			@{KeyPathToBind: ChromatogramResultsGroupKey,ColumnTitle: @"Results Group", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"commentColumn":			@{KeyPathToBind: ChromatogramCommentKey,ColumnTitle: @"Comment", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @NO},
		};
	}
	return columnDescription;
}


- (NSArrayController *)samples {
	return self.tableContent;
}


- (void)viewDidLoad {
	
	if(self.samples && FolderListController.sharedController) {
		/// the samples we show must be those of the selected folder
		[self.samples bind:NSContentSetBinding toObject:FolderListController.sharedController withKeyPath:@"selectedFolder.samples" options:nil];
	}
	
	/// we bind buttons that are within our view to relevant keypaths
	for (NSControl *control in self.view.subviews) {
		if([control isKindOfClass:NSControl.class]) {
			if(control.action == @selector(showImportSamplePanel:)) {
				/// the button to import samples should be disabled when the folder list controller is not in a state that allows importing samples
				[control bind:NSEnabledBinding toObject:FolderListController.sharedController withKeyPath:@"canImportSamples" options:nil];
			} else if(control.action == @selector(editSmartFolder:)) {
				[control bind:NSHiddenBinding toObject:FolderListController.sharedController withKeyPath:@"selectedFolder.isSmartFolder" options:@{NSValueTransformerNameBindingOption : NSNegateBooleanTransformerName}];
				/// the button must also be hidden when no folder is selected.
				[control bind:@"hidden2" toObject:FolderListController.sharedController  withKeyPath:@"selectedFolder" options:@{NSValueTransformerNameBindingOption : NSIsNilTransformerName}];
			} else if([control isKindOfClass:NSSearchField.class]) {
				NSSearchFieldCell *cell = control.cell;		/// the search field allowing to filter by sample name
				if(cell.searchButtonCell) {
					cell.searchButtonCell.image =[NSImage imageNamed:@"filter"];
				}
			}
		}
	}
	
	
	[super viewDidLoad];
	
	/// We allow dropping files from the Finder to the sample table and panels from the panel outline view
	[self.tableView registerForDraggedTypes: @[NSPasteboardTypeFileURL, FolderDragType, SizeStandardDragType]];
	
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


- (NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	NSArray *genotypes = [items valueForKeyPath:@"@unionOfSets.genotypes"];
	if(genotypes.count > 0) {
		return  @"Associated genotypes will be removed as well. \nThis can be undone.";
	}
	
	return [super cautionAlertInformativeStringForItems:items];
}


- (BOOL)shouldDeleteObjectsOnRemove {
	return NO;
}

# pragma mark - managing drag & drop of samples (chromatograms)

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard {
	/// To drag chromatograms between folders
	/// This method is deprecated but convenient as it visually makes the whole row follow the mouse when dragging.
	/// pasteboardWriterForRow would only make the clicked cell move under the mouse, which isn't what we want.
	
	/// We don't drag rows if the clicked row is not among selected rows. This helps the user selects several rows by dragging.
	/// We need to determined the clicked row (NSTableView's -clickedRow returns -1)
	NSPoint mouseLoc = tableView.window.mouseLocationOutsideOfEventStream;
	mouseLoc = [tableView convertPoint:mouseLoc fromView:nil];
	NSInteger row = [tableView rowAtPoint:mouseLoc];
	if(! [tableView.selectedRowIndexes containsIndex:row]) {
		return NO;
	}
	[pboard declareTypes:@[@"samplesDragType"] owner:self];
	/// we won't copy samples to the pasteboard, we just point to them
	NSArray *temp = [self.samples.arrangedObjects objectsAtIndexes:rowIndexes];
	if (temp.count > 0) {
		self.draggedSamples = temp;
		return YES;
	}
	return NO;
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
			self.draggedABIFFilePaths = [FileImporter ABIFilesFromPboard:pboard];
		}
		[tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
		if (self.draggedABIFFilePaths.count > 0) {
			return NSDragOperationCopy;     /// we validate the drop only if at least one ABIF file is dragged
		}
	}
	
	if ([pboard.types containsObject:FolderDragType] || [pboard.types containsObject:SizeStandardDragType]) {
		/// the user drags a panel (folder) or a size standard onto samples. We apply the panel to selected samples
		if(dropOperation == NSTableViewDropAbove) {
			return NSDragOperationNone;
		}
		if([pboard.types containsObject:FolderDragType]) {
			Panel *panel = [self.samples.managedObjectContext objectForURIString:[pboard stringForType:FolderDragType]
																   expectedClass:Panel.class];
			if(!panel) {
				return NSDragOperationNone;				/// only panels can be dropped
			}
		}
		if([self.samples.arrangedObjects count] > 0) {
			[tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
		}
		tableView.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleRegular;
		/// We don't show anything special because a panel is not a row to be inserted (I would be better to highlight the selected rows)
		return NSDragOperationCopy;
	}
	
	return NO;
}



- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
	NSPasteboard *pboard = info.draggingPasteboard;
	if ([pboard.types containsObject:NSPasteboardTypeFileURL] ) {
		if(self.draggedABIFFilePaths.count > 0) {
			SampleFolder *destination = FolderListController.sharedController.selectedFolder;
			if(destination) {
				[self addSamplesFromFiles:self.draggedABIFFilePaths toFolder:destination];
			}
		}
		return YES;
	}
	if ([pboard.types containsObject:FolderDragType] ) {
		if([self.samples.arrangedObjects count] == 0) {
			return NO;
		}
		Panel *panel = [self.samples.managedObjectContext objectForURIString:[pboard stringForType:FolderDragType]
															   expectedClass:Panel.class];
		if(!panel) {
			return NO;
		}
		[self applyPanel:panel toSamples:self.samples.arrangedObjects];
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
		
		[self applySizeStandard:draggedSizeStandard toSamples:self.samples.arrangedObjects];
		return YES;
	}
	
	return NO;
}

- (void)tableView:(NSTableView *)tableView draggingSession:(nonnull NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	self.draggedSamples = NSArray.new;		/// if the dragging session ended, we remove everything from the dragged samples array
}


/// when the user clicks one of the selected rows and the table is not active, this should not deselect other rows.
/// We implement this behavior as we expect user to frequently switch between sample table and genotype table
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
	if(MainWindowController.sharedController.sourceController == self) return YES;
	return ![self.samples.selectionIndexes containsIndex: row];
	
}


#pragma mark - managing the table's contextual menu

- (BOOL)validateMenuItem:(NSMenuItem *)item {
	BOOL response = [super validateMenuItem:item];
	if(item.hidden) {
		return NO;					/// the item may have been hidden in our superclass' menuNeedsUpdate (usually,
									/// if the item is part of the tableViews's menu and no row is clicked).
	}
	if(!response) {
		return NO;
	}
	
	if(item.action == @selector(showImportSamplePanel:)) {
		return FolderListController.sharedController.canImportSamples;
	}
	
	NSArray *targets = [self targetItemsOfSender:item];
	
	if(item.action == @selector(showGenotypes:)) {
		NSArray *genotypes = [targets valueForKeyPath:@"@unionOfSets.genotypes"];
		if(genotypes.count == 0) {
			return NO;
		}
		NSArray *shownGenotypes = GenotypeTableController.sharedController.genotypes.arrangedObjects;
		for(Genotype *genotype in genotypes) {
			if([shownGenotypes indexOfObjectIdenticalTo:genotype] != NSNotFound) {
				return YES;
			}
		}
		return NO;
	}
	
	if(item.action == @selector(callAlleles:)) {
		for(Chromatogram *sample in targets) {
			if(sample.genotypes.count > 0 && sample.sizingQuality.floatValue > 0) {
				return YES;
			}
		}
		return NO;
	}
	
	if(item.action == @selector(revealInParentFolder:)) {
		if (FolderListController.sharedController.selectedFolder.isSmartFolder) {
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
		return [FolderListController.sharedController validateMenuItem:item];
	}
	
	return YES;
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	NSArray *targetSamples = [self targetItemsOfSender:menu.itemArray.firstObject];
	if([menu.identifier isEqualToString:@"Standards"]) {
		/// the submenu allowing to apply a size standard to samples.
		/// we determine the size standard of target samples so as to set the state of the equivalent menu item to on (tick-mark).
		NSArray *sizeStandards = [targetSamples valueForKeyPath:@"@distinctUnionOfObjects.sizeStandard"];
		SizeStandard *currentStandard = nil;
		if(sizeStandards.count == 1) {
			currentStandard = sizeStandards.firstObject;
		}
		[menu removeAllItems];
		for(SizeStandard *standard in SizeStandardTableController.sharedController.tableContent.arrangedObjects) {
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
				/// because our recursive method below only returns an NSMenu (which cannot replace the "menu" argument in menuNeedsUpdate)
				if (PanelListController.sharedController.rootFolder.subfolders > 0) {
					item.hidden = NO;
					item.submenu = [self menuForPanels:PanelListController.sharedController.rootFolder.subfolders];	/// we populate it with a hierarchical menu representing the available panels within folders
				} else {
					item.hidden = YES;													/// we don't show it if there is no panel
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
	
	[super menuNeedsUpdate:menu];
}

- (NSMenu *)menuForPanels:(NSOrderedSet *)panelFolders {
	if(!panelFolders.count) {
		return nil;
	}
	NSMenu *menu = NSMenu.new;
	for(PanelFolder *panelFolder in panelFolders) {
		BOOL isPanel = panelFolder.isPanel;
		if(!isPanel && panelFolder.subfolders.count == 0) {
			continue;
		}
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:panelFolder.name action:@selector(applyPanel:) keyEquivalent:@""];
		item.offStateImage = isPanel? [NSImage imageNamed:@"panelBadgeMenu"] : [NSImage imageNamed:@"folderBadge"];
		[menu addItem:item];
		if(isPanel) {
			item.target = self;
			item.representedObject = panelFolder;
		} else {
			item.action = nil;
			item.submenu = [self menuForPanels:panelFolder.subfolders];
		}
	}
	return menu;
}




#pragma mark - user actions on samples

/// Applies a size standard (inferred from the sender) to target samples.
- (IBAction)applySizeStandard:(id)sender {
	SizeStandard *standard;
	if([sender class] == NSMenuItem.class) {
		standard = [sender representedObject];
	} else {
		standard = SizeStandardTableController.sharedController.tableContent.selectedObjects.firstObject;
	}
	if(!standard) {
		return;
	}
	[self applySizeStandard:standard toSamples:[self targetItemsOfSender:sender]];
}

/// Applies the standard to samples in sampleArray
- (void)applySizeStandard:(SizeStandard*) standard toSamples:(NSArray <Chromatogram *> *)sampleArray {
	for (Chromatogram *sample in sampleArray) {
		[sample applySizeStandard:standard];		/// we don't do that in a child context without undo manager to save time, as this would require materializing samples in the other context, which would be worse.
	}
	[self.undoManager setActionName:@"Apply Size Standard"];
	[(AppDelegate *)NSApp.delegate saveAction:self];
	
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
	for(Chromatogram *sample in [self targetItemsOfSender:sender]) {
		Chromatogram *copy = sample.copy;
		copy.folder = sample.folder;
		sample.polynomialOrder = order;
	}
	[(AppDelegate *)NSApp.delegate saveAction:self];
}


/// Applies a panel (inferred from the sender) to target samples.
- (IBAction)applyPanel:(id)sender {
	
	Panel *panel;
	if([sender class] == NSMenuItem.class) {
		panel = [sender representedObject];
	} else {
		panel = (Panel *)PanelListController.sharedController.selectedFolder;
	}
	if(!panel.isPanel) {
		return;
	}
	[self applyPanel:panel toSamples: [self targetItemsOfSender:sender]];
	
}

/// Applies panel to each sample of sampleArray.
- (void)applyPanel:(Panel*) panel toSamples:(NSArray <Chromatogram *>*)sampleArray {
	/// We don't do this in a child context as it takes longer
	NSMutableArray *errors = NSMutableArray.new;
	NSMutableArray *validSamples = NSMutableArray.new;
	for(Chromatogram *sample in sampleArray) {
		NSError *error;
		if([sample validateValue:&panel forKey:ChromatogramPanelKey error:&error]) {
			[validSamples addObject:sample];
		} else if(error) {
			[errors addObject:error];
		}
	}
	if(validSamples.count > 0) {
		[self.undoManager setActionName:@"Apply Marker Panel"];
	}
	/// the reason why we used the validSamples array is to set the panel's samples in one operation
	/// so that it posts only one PanelSampleDidChange notification.
	if(validSamples.count > 0) {
		NSString *alleleName = [NSUserDefaults.standardUserDefaults stringForKey:MissingAlleleName];
		[panel addSamples:[NSSet setWithArray:validSamples]];
		for(Chromatogram *sample in validSamples) {
			[sample applyPanelWithAlleleName:alleleName];
		}
	}
	
	if(errors.count > 0) {
		NSError *error;
		if(errors.count == 1) {
			error = errors.firstObject;
		} else {
			NSString *description = [NSString stringWithFormat:@"Panel '%@' could not be applied to %ld sample(s).", panel.name, errors.count];
			error = [NSError errorWithDomain:@"jpeccoud.STRYper"
										code:NSManagedObjectValidationError
									userInfo:@{NSDetailedErrorsKey: [NSArray arrayWithArray:errors],
											   NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
											   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"See the error log for details.", nil)
											 }];
		}
		[MainWindowController.sharedController showAlertForError:error];
	}
	[(AppDelegate *)NSApp.delegate saveAction:self];
	
}



- (IBAction)callAlleles:(id)sender {
	
	NSArray *samples =[self targetItemsOfSender:sender];
	for(Chromatogram *sample in samples) {
		for (Genotype *genotype in sample.genotypes) {
			[genotype callAlleles];
		}
	}
	[self.undoManager setActionName:@"Call Alleles"];
	[(AppDelegate *)NSApp.delegate saveAction:self];
	
}


/// Selects the genotypes associated with target samples
- (IBAction)showGenotypes:(id)sender {
	NSArray *gen = [[self targetItemsOfSender:sender] valueForKeyPath:@"@unionOfSets.genotypes"];
	
	MainWindowController.sharedController.sourceController = GenotypeTableController.sharedController;		/// we activate the genotype table
	
	[GenotypeTableController.sharedController.genotypes setSelectedObjects:gen];
	NSTableView *genotypeTable = GenotypeTableController.sharedController.tableView;
	if(genotypeTable) {
		NSInteger row = genotypeTable.selectedRow;
		if(row >= 0) {
			[genotypeTable scrollRowToVisible:row];
		}
	}
	
}


- (IBAction) revealInParentFolder:(id)sender {
	/// if we show the contents of a smart folder, this allows selecting the parent folder of clicked samples, only if they all belong to the same folder
	NSArray *targetSamples = [self targetItemsOfSender:sender];
	NSArray *folders = [targetSamples valueForKeyPath:@"@distinctUnionOfObjects.folder"];
	if(folders.count != 1) {
		return;
	}
	Folder *folder = folders.firstObject;
	[FolderListController.sharedController selectFolder:folder];
	[self.samples setSelectedObjects:targetSamples];
	NSInteger row = self.tableView.selectedRow;
	if(row >= 0) {
		[self.tableView scrollRowToVisible:row];
	}
}


/// puts target samples into the trash folder (which is emptied when the application quits)
- (void)removeItems:(NSArray *)items {
	NSSet *samples = [NSSet setWithArray:items];
	SampleFolder *selectedFolder = FolderListController.sharedController.selectedFolder;
	if([selectedFolder respondsToSelector:@selector(removeSamples:)]) {
		/// we remove samples from the selected folder in one go, otherwise,  the sample table would update for each removed sample that is added
		/// to the trash folder in the next instruction. That may take some time if many samples are removed
		[selectedFolder removeSamples:samples];
	}
	
	[FolderListController.sharedController.trashFolder addSamples:samples];
	
}

#pragma mark - importing samples

/// imports samples into the selected folder
- (void)showImportSamplePanel:(id)sender {
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
	
	if(!folderListController.selectedFolder) {		/// we only import in the selected folder
		NSAlert *alert = NSAlert.new;
		alert.messageText = @"There is no selected folder to import samples into.";
		alert.informativeText = @"Please select a folder from the sidebar.";
		[alert addButtonWithTitle:@"Ok"];
		[alert beginSheetModalForWindow: window completionHandler:^(NSModalResponse returnCode) {
		}];
		return;
	}
	
	if(!folderListController.canImportSamples) {
		return;
	}
	
	SampleFolder *selectedFolder = folderListController.selectedFolder;
	
	
	NSOpenPanel* panel = NSOpenPanel.openPanel;
	panel.prompt = @"Import";
	panel.canChooseDirectories = NO;
	panel.allowsMultipleSelection = YES;
	panel.message = @"Choose chromatogram files to import into the selected folder.";
	panel.allowedFileTypes = @[@"com.appliedbiosystems.abif.fsa", @"com.appliedbiosystems.abif.hid"];
	[panel beginSheetModalForWindow:window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			[self addSamplesFromFiles:[panel.URLs valueForKeyPath:@"@unionOfObjects.path"] toFolder:selectedFolder];
		}
	}];
}


-(void) addSamplesFromFiles:(NSArray <NSString *>*)filePaths toFolder:(SampleFolder *)folder {
	
	[FileImporter.sharedFileImporter importSamplesFromFiles:filePaths completionHandler:^(NSError *error, SampleFolder *scratchFolder) {
		scratchFolder = [folder.managedObjectContext existingObjectWithID:scratchFolder.objectID error:nil];
		if(scratchFolder.samples.count > 0) {
			/// to transfer imported samples to the folder, we need to materialize the scratch folder in the folder's context.
			/// It won't appear in the folder list, as this scratch folder has no parent.
			[folder addSamples:scratchFolder.samples];		/// this updates the sample table only once.
			[self.undoManager setActionName:@"Import Sample(s)"];
			[(AppDelegate *)NSApp.delegate saveAction:self];
		}
		[scratchFolder.managedObjectContext deleteObject:scratchFolder];
		
		if(error && error.code != NSUserCancelledError) {
			/// we did not manage the error first, as the operation above may block the UI (hence the dismissal of any error alert) if many samples are imported
			[MainWindowController.sharedController showAlertForError:error];
		}
	}];
}



-(IBAction)paste:(id)sender {
	FolderListController *sharedController = FolderListController.sharedController;
	if(!sharedController.canImportSamples) {
		/// There may be no valid selected folder to paste sample into, in which case we do nothing.
		return;
	}
	NSPasteboard *pboard = NSPasteboard.generalPasteboard;
	NSArray *items;
	if([pboard.types containsObject:ChromatogramCombinedPasteboardType]) {
		NSString *string = [pboard stringForType:ChromatogramCombinedPasteboardType];
		items = [string componentsSeparatedByString:@"\n"];
	} else if([pboard.types containsObject:ChromatogramPasteboardType]) {
		items = pboard.pasteboardItems;
	} else {
		return;
	}
	SampleFolder *selectedFolder = sharedController.selectedFolder;
	[self pasteSamplesFromItems:items completionHandler:^(NSError *error, SampleFolder *folder) {
		/// to transfer pasted samples to the table, we need to materialize the folder in our context.
		/// It won't appear in the folder list, as this scratch folder has no parent.
		
		folder = [self.samples.managedObjectContext existingObjectWithID:folder.objectID error:nil];
		NSSet *copiedSamples = folder.samples;
		
		if(copiedSamples.count > 0) {
			if(sharedController.selectedFolder != selectedFolder) {
				[sharedController selectFolder:selectedFolder];
			}
			NSString *action = copiedSamples.count > 1? @"Paste Samples" : @"Paste Sample";
			[self.samples addObjects:copiedSamples.allObjects];	/// which automatically selects the copied samples
			[self.tableView scrollRowToVisible:self.tableView.selectedRow];
			
			[(AppDelegate *)NSApp.delegate saveAction:nil];
			[self.undoManager setActionName:action];
		}
		[folder.managedObjectContext deleteObject:folder];
		
		if(error && error.code != NSUserCancelledError) {
			/// we did not manage the error first, as the operation above may block the UI (hence the dismissal of any error alert) if many samples are imported
			[MainWindowController.sharedController showAlertForError:error];
		}
	}];
	
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
			NSError *copyError;
			numberOfCopiedSamples++;
			
			NSString *URIString;
			if([item isKindOfClass:NSPasteboardItem.class]) {
				URIString = [item stringForType:ChromatogramPasteboardType];
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
		
		[pasteProgress resignCurrent];
		
		if(pasteProgress.isCancelled) {
			error = [NSError cancelOperationErrorWithDescription:@"The user cancelled the operation." suggestion:@""];
		} else if(folder.samples.count > 0 && folder.managedObjectContext.hasChanges) {
			pasteProgress.localizedDescription = @"Saving copied samples…";
			pasteProgress.cancellable = NO;
			[folder.managedObjectContext save:&error];
			
			if(error) {
				error = [NSError errorWithDescription:@"The sample(s) could not be pasted because an error occurred saving the database."
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
										userInfo:@{NSDetailedErrorsKey: [NSArray arrayWithArray:copyErrors],
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


- (NSPasteboardType)pasteboardTypeForCombinedItems {
	return ChromatogramCombinedPasteboardType;
}

@end
