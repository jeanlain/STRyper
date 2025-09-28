//
//  GenotypeTableController.m
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



#import "GenotypeTableController.h"
#import "MainWindowController.h"
#import "Chromatogram.h"
#import "Genotype.h"
#import "Mmarker.h"
#import "Panel.h"
#import "SampleTableController.h"
#import "FolderListController.h"
#import "IndexImageView.h"
#import "AggregatePredicateEditorRowTemplate.h"
#import "Allele.h"
#import "MarkerTableController.h"

@interface GenotypeTableController ()

/// A variable bound to the genotypes shown in the genotype table.
@property (nonatomic) NSArray *genotypeContent;

@property (nonatomic) NSDictionary<NSString *, NSString *> *actionNamesForColumnIDs;

@end


@implementation GenotypeTableController {
	
	IBOutlet NSView *exportPanelAccessoryView;
	BOOL exportSelectionOnly;
	NSDictionary *columnDescription;
	NSArray<NSImage *> *statusImages;		/// The images that represent the different genotype statuses.
	NSMutableDictionary *filterDictionary;	/// To save filters to the user defaults, for each folder that has a filter
	__weak SampleFolder *currentFolder; 	/// To update filters and selected rows, which are associated to sample folders
}


+ (instancetype)sharedController {
	static GenotypeTableController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (NSNibName)nibName {
	return @"GenotypeTab";
}


- (NSString *)nameForItem:(id)item {
	return self.entityName;
}


- (void)viewDidLoad {
	[super viewDidLoad];

	/// the order of the image in the array corresponds to genotypeStatus property of genotypes (an integer)
	statusImages = @[[NSImage imageNamed:ACImageNameCircle],
					 [NSImage imageNamed:ACImageNameZero],
					 [NSImage imageNamed:ACImageNameFilledCircle],
					 [NSImage imageNamed:ACImageNameDanger],
					 [NSImage imageNamed:NSImageNameStatusPartiallyAvailable],
					 [NSImage imageNamed:ACImageNameEditedRound],
					 [NSImage imageNamed:ACImageNameStopSign]];
	
	if(SampleTableController.sharedController.samples) {
		
		[self bind:ContentArrayBinding
		  toObject:SampleTableController.sharedController.samples
	   withKeyPath:@"arrangedObjects.@unionOfSets.genotypes" options:nil];
		
	}
}


- (NSString *)entityName {
	return Genotype.entity.name;
}


- (NSArrayController *)genotypes {
	return self.tableContent;
}


- (NSDictionary *)columnDescription {
	if(!columnDescription) {
		columnDescription = @{
			@"genotypeSampleColumn":	@{KeyPathToBind: @"sample.sampleName",ColumnTitle: @"Sample", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Name of source sample"},
			@"genotypeStatusColumn":	@{KeyPathToBind: @"statusText", ImageIndexBinding: @"status" ,ColumnTitle: @"Status", CellViewID: @"imageCellView", IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Status of genotype calling"},
			@"genotypePanelColumn":		@{KeyPathToBind: @"sample.panel.name",ColumnTitle: @"Panel", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Panel of the genotype's marker"},
			@"genotypeMarkerColumn":	@{KeyPathToBind: @"marker.name", ColumnTitle: @"Marker", CellViewID: @"compositeCellViewText", ImageIndexBinding: @"marker.channel", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Molecular marker of the genotype"},
			@"genotypeHeight1Column":		@{KeyPathToBind: @"allele1.height",ColumnTitle: @"Height1", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, HeaderToolTip:@"Height of the shorter allele's peak (RFU)"},
			 @"genotypeHeight2Column":		@{KeyPathToBind: @"allele2.height",ColumnTitle: @"Height2", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, HeaderToolTip:@"Height of the longer allele's peak (RFU)"},
			@"genotypeSize1Column":		@{KeyPathToBind: @"allele1.visibleSize",ColumnTitle: @"Size1", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Estimated size of the shorter allele (bp)"},
			@"genotypeSize2Column":		@{KeyPathToBind: @"allele2.visibleSize",ColumnTitle: @"Size2", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Estimated size of the longer allele (bp)"},
			@"genotypeAllele1Column":	@{KeyPathToBind: @"allele1.name",ColumnTitle: @"Allele1", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Name of the shorter allele (editable)"},
			@"genotypeAllele2Column":	@{KeyPathToBind: @"allele2.name",ColumnTitle: @"Allele2", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Name of the longer allele (editable)"},
			@"genotypeOffsetColumn":	@{KeyPathToBind: @"offsetString",ColumnTitle: @"Offset", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Applied offset at the marker"},
			@"additionalFragmentsColumn":	@{KeyPathToBind: @"additionalFragmentString",ColumnTitle: @"Additional Peaks", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @NO, HeaderToolTip:@"Additional peak(s) detected (size:name)"},
			@"genotypeNotesColumn":	@{KeyPathToBind: @"notes",ColumnTitle: @"Notes", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES, HeaderToolTip:@"Editable notes"}
		};
	}
	return columnDescription;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	return @[@"genotypeStatusColumn", @"genotypeSampleColumn", @"genotypePanelColumn",@"genotypeMarkerColumn",
			 @"genotypeSize1Column",@"genotypeSize2Column", @"genotypeAllele1Column", @"genotypeAllele2Column", @"genotypeHeight1Column", @"genotypeHeight2Column", @"genotypeOffsetColumn", @"additionalFragmentsColumn", @"genotypeNotesColumn"];
}


- (BOOL)canHideColumn:(NSTableColumn *)column {
	NSString *ID = column.identifier;
	return ![ID isEqualToString: @"genotypeSampleColumn"] && ![ID isEqualToString: @"genotypeStatusColumn"];
}


- (NSSortDescriptor *)sortDescriptorPrototypeForTableColumn:(NSTableColumn *)column {
	if([column.identifier isEqualToString:@"genotypeSampleColumn"]) {
		return [NSSortDescriptor sortDescriptorWithKey:@"sample.uniqueName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
	}
	
	if([column.identifier isEqualToString:@"genotypeStatusColumn"]) {
		return [NSSortDescriptor sortDescriptorWithKey:@"status" ascending:YES];
	}

	return [super sortDescriptorPrototypeForTableColumn:column];
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
		_actionNamesForColumnIDs = @{@"genotypeAllele2Column": @"Rename Allele",
									 @"genotypeAllele1Column": @"Rename Allele",
									 @"genotypeNotesColumn": @"Edit Genotype Notes"
		};
	}
	return _actionNamesForColumnIDs;
}


- (NSTableView *)viewForCellPrototypes {
	return SampleTableController.sharedController.tableView;
}


- (BOOL)shouldMakeTableHeaderMenu {
	return YES;
}


- (BOOL)shouldDeleteObjectsOnRemove {
	return NO;			/// one cannot delete a genotype from the table
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *ID = tableColumn.identifier;
	
	if([@[@"genotypeAllele2Column", @"genotypeSize2Column", @"genotypeHeight2Column"] containsObject:ID]) {
		/// if the genotype is haploid, the columns for allele 2 should have no cell
		NSArray *genotypes = self.genotypes.arrangedObjects;
		if(genotypes.count > row) {
			Genotype *gen = genotypes[row];
			if(gen.assignedAlleles.count < 2) {
				return nil;
			}
		}
	}
	
	NSTableCellView *view = (NSTableCellView *)[super tableView:tableView viewForTableColumn:tableColumn row:row];
	
	if([ID isEqualToString:@"genotypeStatusColumn"]) {
		IndexImageView *imageView = (IndexImageView *)view.imageView;
		if([imageView respondsToSelector:@selector(imageArray)] && imageView.imageArray == nil) {
			imageView.imageArray = statusImages;
		}
	}
	
	if([ID isEqualToString:@"genotypeMarkerColumn"]) {
		IndexImageView *imageView = (IndexImageView *)view.imageView;
		if([imageView respondsToSelector:@selector(imageArray)] && imageView.imageArray == nil) {
			imageView.imageArray = MarkerTableController.channelColorImages;
		}
	}
	
	return view;
	
}


- (void)_loadContent {
	[super _loadContent];
	SampleFolder *selectedFolder = FolderListController.sharedController.selectedFolder;
	if(selectedFolder && selectedFolder != currentFolder) {
		currentFolder = selectedFolder;
		[self filterGenotypesOfSelectedFolder];
		[self restoreSelectedItems];
	}
}

#pragma mark - user actions on genotypes


- (NSArray *)validTargetsOfSender:(id)sender {
	NSArray *targetGenotypes = [super validTargetsOfSender:sender];
	BOOL fromContextMenu = [sender respondsToSelector:@selector(topMenu)] && [sender topMenu] == self.tableView.menu;
	if([sender action] == @selector(binAlleles:) || [sender action] == @selector(callAlleles:)) {
		if(!fromContextMenu) {
			/// If the sender is not from the table's contextual menu, its potential targets are all listed genotypes
			targetGenotypes = self.genotypes.arrangedObjects;
		}
		targetGenotypes = [targetGenotypes filteredArrayUsingBlock:^BOOL(Genotype*  _Nonnull genotype, NSUInteger idx) {
			/// We don't bin/call alleles of samples that are not sized, or genotypes that have been edited manually, except when called from the contextual menu
			GenotypeStatus status = genotype.status;
			return  status != genotypeStatusNoSizing && (fromContextMenu || status != genotypeStatusManual);
		}];
	} else if([sender action] == @selector(removeOffsets:)) {
		targetGenotypes = [targetGenotypes filteredArrayUsingBlock:^BOOL(Genotype*  _Nonnull genotype, NSUInteger idx) {
			/// Only genotypes with an offset are relavant.
			MarkerOffset offset = genotype.offset;
			return  offset.intercept != 0.0 || offset.slope != 1.0;
		}];
	} else if([sender action] == @selector(removeAdditionalFragments:)) {
		targetGenotypes = [targetGenotypes filteredArrayUsingBlock:^BOOL(Genotype*  _Nonnull genotype, NSUInteger idx){
			return  genotype.additionalFragments.count > 0;
		}];
	} else if([sender action] == @selector(exportSelection:) && !fromContextMenu) {
		/// All genotypes can be exported.
		targetGenotypes = self.genotypes.arrangedObjects;
	}
	
	return targetGenotypes.count > 0 ? targetGenotypes : nil;
}



- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
	/// One cannot drag a row of the table.
	return nil;
}


- (nullable NSString *)deleteActionTitleForItems:(NSArray *)items {
	return nil;  /// one cannot remove a genotype. It is removed only when a marker is no longer applied to a sample.
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(pasteOffset:)) {
		NSDictionary *dic = Chromatogram.markerOffsetDictionaryFromGeneralPasteBoard;
		if(dic) {
			NSArray *genotypes = [self validTargetsOfSender:menuItem];
			NSArray *URIs = dic.allKeys;
			for(Genotype *genotype in genotypes) {
				NSString *URI = genotype.marker.objectID.URIRepresentation.absoluteString;
				if([URIs containsObject:URI]) {
					menuItem.hidden = NO;
					return YES;
				}
			}
		}
		menuItem.hidden = YES;
		return NO;
	}
	return [super validateMenuItem:menuItem];
}


- (void)remove:(id)sender {
	/// The UI doesn't allow removing genotypes. They can only be removed by removing a marker applied to samples
	/// but as a safety measure, we make sure we cannot remove genotypes
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
	/// when the user clicks one of the selected rows and the table is not active, this should not deselect other rows.
	/// We implement this behavior as we expect users to frequently switch between sample table and genotype table
	if(MainWindowController.sharedController.sourceController == self) {
		return YES;
	}
	NSIndexSet *selectedRows = tableView.selectedRowIndexes;
	NSIndexSet *selectedItems = self.genotypes.selectionIndexes;
	return ![selectedItems containsIndexes:selectedRows] || ![selectedItems containsIndex:row];
}


- (IBAction)binAlleles:(id)sender {
	[self.undoManager setActionName:@"Bin Alleles"];
	NSArray *genotypes =  [self validTargetsOfSender:sender];
	BOOL annotateSuppPeaks = [NSUserDefaults.standardUserDefaults boolForKey:AnnotateAdditionalPeaks];
	
	for (Genotype *genotype in genotypes) {
		GenotypeStatus status = genotype.status;
		if(status == genotypeStatusNotCalled || status == genotypeStatusNoPeak) {
			[genotype callAllelesAndAdditionalPeak:annotateSuppPeaks];
		} else {
			[genotype binAlleles];
		}
	}
	
	[AppDelegate.sharedInstance saveAction:self];
}


- (IBAction)callAlleles:(id)sender {
	/// we don't create a managed object context to call alleles as allele call is very quick (less than 1s for 10000 genotypes)
	/// and is actually slower when we use a child context
	[self.undoManager setActionName:@"Find Alleles"];
	NSArray *genotypes = [self validTargetsOfSender:sender];
	BOOL annotateSuppPeaks = [NSUserDefaults.standardUserDefaults boolForKey:AnnotateAdditionalPeaks];

	for (Genotype *genotype in genotypes) {
		[genotype callAllelesAndAdditionalPeak:annotateSuppPeaks];
	}
	
	//[self checkGenotypesForAdenylation:genotypes]; /// deactivated for now, as this may cause genotyping errors.
	[AppDelegate.sharedInstance saveAction:self];
	
}



 /**********debugging******
static NSInteger genotypeIndex = 0;

-(void) processGenotypes {
	NSArray *genotypes = self.genotypes.arrangedObjects;
	if(genotypeIndex < genotypes.count -1) {
		[self.genotypes setSelectionIndex:genotypeIndex];
		[self.tableView scrollRowToVisible:genotypeIndex];
		[NSTimer scheduledTimerWithTimeInterval:0.01f
										 target: self
									   selector: @selector(callAllelesOnCurrentIndex)
									   userInfo: nil
										repeats: NO];
	}
}


-(void)callAllelesOnCurrentIndex {
	NSArray *genotypes = self.genotypes.arrangedObjects;
	if(genotypeIndex < genotypes.count -1) {
		Genotype *genotype = genotypes[genotypeIndex];
		[genotype callAlleles];
		genotypeIndex ++;
		[self processGenotypes];
	}
}
*/



/// Removes the additional fragments of target genotypes
- (IBAction)removeAdditionalFragments:(id)sender {
	[self.undoManager setActionName:@"Remove Additional Peaks"];

	NSArray *genotypes = [self validTargetsOfSender:sender];
	
	for (Genotype *genotype in genotypes) {
		BOOL edited = NO;
		for (Allele *allele in genotype.additionalFragments) {
			[allele removeFromGenotypeAndDelete];
			edited = YES;
		}
		if(edited) {
            genotype.proposedStatus = genotypeStatusManual;
		}
	}
	
	[AppDelegate.sharedInstance saveAction:self];
}


- (IBAction)selectSamples:(id)sender {
	MainWindowController *mainWindowController = MainWindowController.sharedController;
	mainWindowController.sourceController = SampleTableController.sharedController;		/// we activate the sample tableview
	[SampleTableController.sharedController.samples setSelectedObjects:[[self validTargetsOfSender:sender] valueForKeyPath:@"@unionOfObjects.sample"]];
	NSTableView *sampleTable = SampleTableController.sharedController.tableView;
	if(sampleTable) {
		NSInteger row = sampleTable.selectedRow;
		if(row >= 0) {
			[sampleTable scrollRowToVisible:row];
		}
	}
}


- (void)removeOffsets:(id)sender {
	[self.undoManager setActionName:@"Reset Genotype Offset(s)"];
	NSArray *genotypes = [self validTargetsOfSender:sender];
	for(Genotype *genotype in genotypes) {
		genotype.offsetData = nil;
	}
	[AppDelegate.sharedInstance saveAction:self];
}

#pragma mark - export and copy

- (BOOL)canExportItems {
	return YES;
}



- (NSString *)exportActionTitleForItems:(NSArray *)items {
	return items.count > 0? @"Export Genotype Table…" : nil;
}


- (NSImage *)exportButtonImageForItems:(NSArray *)items {
	static NSImage * exportImage;
	if(!exportImage) {
		exportImage = [NSImage imageNamed:ACImageNameExportGenotypes];
	}
	return exportImage;
}


-(IBAction)exportSelectionOnly:(NSButton *)sender {
	exportSelectionOnly = sender.tag == 2;
}


- (IBAction)exportSelection:(id)sender {
	NSArray *targetGenotypes = [self validTargetsOfSender:sender];
	NSArray *selectedGenotypes = self.genotypes.selectedObjects;

	if(targetGenotypes.count == 0) {
		/// Which should not happen
		[NSApp presentError:[NSError errorWithDescription:@"No genotype to export." suggestion:@""]];
		return;
	}
	
	BOOL fromContextualMenu = [sender respondsToSelector:@selector(topMenu)] && [sender topMenu] == self.tableView.menu;
	
	NSSavePanel* panel = NSSavePanel.savePanel;
	panel.message = @"Export genotype table";
	
	if(exportPanelAccessoryView) {
		panel.accessoryView = exportPanelAccessoryView;
		NSButton *exportWholeTableRadioButton = [exportPanelAccessoryView viewWithTag:1];
		NSButton *exportSelectionRadioButton = [exportPanelAccessoryView viewWithTag:2];
		if(fromContextualMenu || selectedGenotypes.count == 0) {
			exportWholeTableRadioButton.state = !fromContextualMenu;
			exportSelectionRadioButton.state = fromContextualMenu;
			exportWholeTableRadioButton.enabled = NO;
			exportSelectionRadioButton.enabled = NO;
		} else {
			exportWholeTableRadioButton.state = NSControlStateValueOn;
			exportSelectionRadioButton.state = NSControlStateValueOff;
			exportWholeTableRadioButton.enabled = YES;
			exportSelectionRadioButton.enabled = YES;
		}
		exportSelectionOnly = exportSelectionRadioButton.state;
	}
	
	panel.nameFieldStringValue = [FolderListController.sharedController.selectedFolder.name stringByAppendingString: @" genotypes.txt"];
	panel.allowedFileTypes = @[@"public.plain-text"];
	
	[panel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSArray *exportedGenotypes = (self->exportSelectionOnly && !fromContextualMenu) ? selectedGenotypes : targetGenotypes;
			NSURL* theFile = panel.URL;
			NSString *exportString = [self stringFromGenotypes:exportedGenotypes withSampleInfo:[NSUserDefaults.standardUserDefaults boolForKey:AddSampleInfo]];
			NSError *error = nil;
			[exportString writeToURL:theFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
			if(error) {
				[NSApp presentError:error];
			}
		}
	}];
	
}


/// creates a string from an array of genotypes based on the table columns
- (NSString *) stringFromGenotypes:(NSArray *)genotypes withSampleInfo: (BOOL)addSampleInfo {
	/// THIS MAY CRASH IF THERE IS NO VISIBLE COLUMN
	NSMutableArray<NSString *> *rows = NSMutableArray.new; /// The strings for all rows

	/// The fields at each row will be added to an array, the first row being the column titles.
	NSMutableArray *fields = [NSMutableArray arrayWithArray:[self.visibleColumns valueForKeyPath:@"@unionOfObjects.title"]];
	
	SampleTableController *sampleTableController = SampleTableController.sharedController;
	NSMutableArray *sampleTableColumns = NSMutableArray.new;
	
	if(addSampleInfo) {
		/// If sample info is added, we avoid redundant columns, like the panel and sample name, which may already be visible in the genotype table.
		/// The "Sample" column is equivalent to the "Name"' column of the sample table.
		NSArray *includedColumnTitles = [fields arrayByAddingObject:@"Name"];
		
		for(NSTableColumn *column in sampleTableController.visibleColumns) {
			NSString *title = column.title;
			if(![includedColumnTitles containsObject:title]) {
				[fields addObject: title];
				[sampleTableColumns addObject:column];
			}
		}
	}
	
	[rows addObject:[fields componentsJoinedByString:@"\t"]];
	for (Genotype *genotype in genotypes) {
		[fields removeAllObjects];
		/// we export data as shown in the table, hence based on the displayed columns and their order
		[fields addObject: [self stringForObject:genotype]];
		if(addSampleInfo) {
			Chromatogram *sample = genotype.sample;
			for (NSTableColumn *column in  sampleTableColumns) {
				[fields addObject: [sampleTableController stringCorrespondingToColumn:column forObject:sample]];
			}
		}
		[rows addObject: [fields componentsJoinedByString:@"\t"]];
	}
	return [rows componentsJoinedByString:@"\n"];
}


- (void)copyItems:(NSArray *)items ToPasteBoard:(NSPasteboard *)pasteboard {
	[super copyItems:items ToPasteBoard:pasteboard];
		
	if(items.count == 1) {
		/// We copy a genotype (its offset) to the pasteboard if only one genotype is copied
		Genotype *genotype = items.firstObject;
		[pasteboard writeObjects: @[genotype]];
	}
}


- (IBAction)pasteOffset:(id)sender {
	NSArray *targetGenotypes = [self validTargetsOfSender:sender];
	NSDictionary *dic = Chromatogram.markerOffsetDictionaryFromGeneralPasteBoard;
	if(!dic || targetGenotypes.count < 1) {
		return;
	}
	BOOL pasted = NO;
	for(Genotype *genotype in targetGenotypes) {
		NSString *URI = genotype.marker.objectID.URIRepresentation.absoluteString;
		NSData *offsetData = dic[URI];
		if([offsetData isKindOfClass:NSData.class] && offsetData.length == sizeof(MarkerOffset)) {
			genotype.offsetData = offsetData;
			pasted = YES;
		}
	}
	
	if(pasted) {
		[self.undoManager setActionName:@"Paste Marker Offset"];
	}
}


#pragma mark - genotype filtering

UserDefaultKey GenotypeFiltersKey = @"genotypeFiltersKey";


- (void)setFilterButton:(NSButton *)filterButton {
	super.filterButton = filterButton;
	[filterButton bind:NSEnabledBinding toObject:self.genotypes withKeyPath:@"content.@count" options:nil];
}


- (void)configurePredicateEditor:(NSPredicateEditor *)predicateEditor {
	/// we prepare the keyPaths (attributes) that the predicate editor will allow filtering.
	/// The first we add will be use to generate predicate editor row template "automatically" via core data.
		
	NSArray *keyPaths = @[@"marker.name", @"marker.panel.name", @"notes"];
	
	NSArray<NSPredicateEditorRowTemplate *> *rowTemplates = [NSPredicateEditorRowTemplate templatesWithAttributeKeyPaths:keyPaths inEntityDescription:Genotype.entity];
	
	/// To filter according to genotype status, we prepare right expressions for the predicate row template.
	NSMutableArray *expressions = [NSMutableArray arrayWithCapacity:6];
	for(NSNumber *status in @[@(genotypeStatusNotCalled),
							  @(genotypeStatusNoPeak),
							  @(genotypeStatusAutomatic),
							  @(genotypeStatusSizingChanged),
							  @(genotypeStatusMarkerChanged),
							  @(genotypeStatusManual),
							  @(genotypeStatusNoSizing)]) {
		[expressions addObject:[NSExpression expressionForConstantValue:status]];
	}
	
	/// We add row templates to filter according to allele properties, which are to-many relationships
	
	NSPredicateEditorRowTemplate *statusTemplate = [[NSPredicateEditorRowTemplate alloc]
													initWithLeftExpressions:@[[NSExpression expressionForKeyPath:@"status"]]
													rightExpressions:expressions
													modifier:NSDirectPredicateModifier
													operators:@[@(NSEqualToPredicateOperatorType), @(NSNotEqualToPredicateOperatorType)]
													options:0];
	
	NSPredicateEditorRowTemplate *alleleNameTemplate = [[AggregatePredicateEditorRowTemplate alloc]
														initWithLeftExpressions:@[[NSExpression expressionForKeyPath:@"assignedAlleles.name"]]
														rightExpressionAttributeType:NSStringAttributeType
														modifier:NSAnyPredicateModifier
														operators:rowTemplates.firstObject.operators
														options:0];
	
	NSPredicateEditorRowTemplate *alleleSizeTemplate = [[AggregatePredicateEditorRowTemplate alloc]
														initWithLeftExpressions:@[[NSExpression expressionForKeyPath:@"assignedAlleles.size"]]
														rightExpressionAttributeType:NSFloatAttributeType
														modifier:NSAnyPredicateModifier
														operators:@[@(NSGreaterThanPredicateOperatorType), @(NSLessThanPredicateOperatorType)]
														options:0];
	
	NSPredicateEditorRowTemplate *alleleHeightTemplate = [[AggregatePredicateEditorRowTemplate alloc]
														initWithLeftExpressions:@[[NSExpression expressionForKeyPath:@"assignedAlleles.height"]]
														rightExpressionAttributeType:NSInteger16AttributeType
														modifier:NSAnyPredicateModifier
														operators:@[@(NSGreaterThanPredicateOperatorType), @(NSLessThanPredicateOperatorType)]
														options:0];
	
	NSPredicateEditorRowTemplate *interceptTemplate = [[NSPredicateEditorRowTemplate alloc]
														initWithLeftExpressions:@[[NSExpression expressionForKeyPath:NSStringFromSelector(@selector(offsetIntercept))]]
														rightExpressionAttributeType:NSFloatAttributeType
														modifier:NSDirectPredicateModifier
														operators:@[@(NSGreaterThanPredicateOperatorType), @(NSLessThanPredicateOperatorType), @(NSEqualToPredicateOperatorType), @(NSNotEqualToPredicateOperatorType)]
														options:0];
	
			
	NSArray *finalTemplates = [@[statusTemplate, alleleNameTemplate, alleleSizeTemplate, alleleHeightTemplate] arrayByAddingObjectsFromArray:rowTemplates];
	 finalTemplates = [finalTemplates arrayByAddingObject:interceptTemplate];
	
	NSArray *compoundTypes = @[@(NSNotPredicateType), @(NSAndPredicateType),  @(NSOrPredicateType)];
	NSPredicateEditorRowTemplate *compound = [[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:compoundTypes];
			
	predicateEditor.rowTemplates = [@[compound] arrayByAddingObjectsFromArray:finalTemplates];
	predicateEditor.canRemoveAllRows = NO;
	
	/// We create a formatting dictionary to translate attribute names into menu item titles. We don't translate other fields (operators)
	keyPaths = [@[@"status", @"assignedAlleles.name", @"assignedAlleles.size", @"assignedAlleles.height"] arrayByAddingObjectsFromArray:keyPaths];
	keyPaths = [keyPaths arrayByAddingObject:NSStringFromSelector(@selector(offsetIntercept))];

	/// The titles for the menu items of the editor left popup buttons
	NSArray *titles = @[@"Status", @"Allele Name", @"Allele Size", @"Allele Height", @"Marker Name", @"Panel Name", @"Notes", @"Offset"];

	NSMutableArray *keys = NSMutableArray.new;		/// the future keys of the dictionary
	for(NSString *keyPath in keyPaths) {
		if([keyPath isEqualToString:@"status"]) {
			/// We need to translate each status number into a string.
			for (GenotypeStatus status = genotypeStatusNotCalled; status <= genotypeStatusNoSizing; status++) {
				NSString *key = [NSString stringWithFormat: @"%@%@%@%d%@",  @"%[", keyPath, @"]@ %@ %[", status, @"]@"];
				[keys addObject:key];
			}
		} else {
			NSString *key = [NSString stringWithFormat: @"%@%@%@",  @"%[", keyPath, @"]@ %@ %@"];		/// see https://funwithobjc.tumblr.com/post/1482915398/localizing-nspredicateeditor
			if([@[@"assignedAlleles.name", @"assignedAlleles.size", @"assignedAlleles.height"] containsObject:keyPath]) {
				key = [key stringByAppendingString: @" %@"];
			}
			[keys addObject:key];
		}
	}
	
	NSMutableArray *values = NSMutableArray.new;	/// the future values
	for(NSString *title in titles) {
		if([title isEqualToString:@"Status"]) {
			/// The different genotype statuses.
			NSArray *menuItemTitles = @[@"Not called", @"No peak found", @"Called", @"Sizing has changed", @"Marker has changed", @"Edited manually", @"Sample not sized!"];
			for (NSString *menuItemTitle in menuItemTitles) {
				NSString *value = [NSString stringWithFormat: @"%@%@%@%@%@",  @"%1$[", title, @"]@ %2$@ %3$[", menuItemTitle, @"]@"];
				[values addObject:value];
			}
		} else {
			NSString *value;
			if([@[@"Allele Name", @"Allele Size", @"Allele Height"] containsObject:title]) {
				/// The segmented control, which is at the right of the first popup button in the template is moved left.
				value = [NSString stringWithFormat: @"%@%@%@",  @"%2$@ %1$[", title, @"]@ %3$@ %4$@"];
			} else {
				value = [NSString stringWithFormat: @"%@%@%@",  @"%1$[", title, @"]@ %2$@ %3$@"];
			}
			[values addObject:value];
		}
	}
	
	predicateEditor.formattingDictionary = [NSDictionary dictionaryWithObjects:values forKeys:keys];
	
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(ruleEditorRowsDidChange:)
											   name:NSRuleEditorRowsDidChangeNotification
											 object:predicateEditor];

}


- (NSPredicate *)defaultFilterPredicate {
	return [NSPredicate predicateWithFormat: @"ANY assignedAlleles.name ==[c] ''"];
}


- (void)applyFilterPredicate:(NSPredicate *)filterPredicate {
	if(self.genotypes.filterPredicate != filterPredicate) {
		[self recordFilterPredicate:filterPredicate];
	}
	[super applyFilterPredicate:filterPredicate];
}


/// Associates the filter predicate to the selected folder in the user defaults
-(void)recordFilterPredicate:(NSPredicate *)filterPredicate {
	Folder *selectedFolder = FolderListController.sharedController.selectedFolder;
	if(!selectedFolder) {
		return;
	}
	
	if(selectedFolder.objectID.isTemporaryID) {
		if(![selectedFolder.managedObjectContext obtainPermanentIDsForObjects:@[selectedFolder] error:nil]) {
			return;
		}
	}
	
	NSString *key = selectedFolder.objectID.URIRepresentation.absoluteString;
	
	if(!filterDictionary) {
		filterDictionary = [NSUserDefaults.standardUserDefaults dictionaryForKey:GenotypeFiltersKey].mutableCopy;
		if(!filterDictionary) {
			filterDictionary = NSMutableDictionary.new;
		}
	}
	
	NSData *filterPredicateData;
	if(filterPredicate) {
		filterPredicateData = [NSKeyedArchiver archivedDataWithRootObject:filterPredicate
								requiringSecureCoding:YES
												error:nil];

	}
	
	if(filterPredicateData) {
		filterDictionary[key] = filterPredicateData;
	} else {
		[filterDictionary removeObjectForKey:key];
	}
	
	[NSUserDefaults.standardUserDefaults setObject:filterDictionary forKey:GenotypeFiltersKey];
}

/// Applies the filter associated to the selected folder to the table, retrieving it from the user defaults
-(void) filterGenotypesOfSelectedFolder {
	if(!filterDictionary) {
		filterDictionary = [NSUserDefaults.standardUserDefaults dictionaryForKey:GenotypeFiltersKey].mutableCopy;
		if(!filterDictionary) {
			self.genotypes.filterPredicate = nil;
			return;
		}
	}
	
	NSString *key = FolderListController.sharedController.selectedFolder.objectID.URIRepresentation.absoluteString;
	if(key) {
		NSData *predicateData = filterDictionary[key];
		if([predicateData isKindOfClass:NSData.class]) {
			NSPredicate *filterPredicate = [NSKeyedUnarchiver unarchivedObjectOfClass:NSPredicate.class fromData:predicateData error:nil];
			[filterPredicate allowEvaluation];
			self.genotypes.filterPredicate = filterPredicate;
			return;
		}
	}
	self.genotypes.filterPredicate = nil;
}


- (void)ruleEditorRowsDidChange:(NSNotification *)notification {
	/// We use this notification to add status images to the popup button allowing to filter by status.
	/// I haven't found a better solution. Providing an custom popup button in -templateViews of `NSRuleEditorRowTemplate` subclass doesn't work
	/// because the predicate editor only take the menu item titles to create its own popup button.
	/// Subclassing `NSRuleEditor` would certainly be the best solution, but it would require much more effort.
	NSPredicateEditor *editor = notification.object;
	NSView *view = editor.subviews.firstObject;
	for(NSView *row in view.subviews) {
		/// Hopefully, we are enumerating the rows of the editor (among other subviews).
		if(row.subviews.count < 4) {
			continue;
		}
		for(NSView *subview in row.subviews) {
			if([subview isKindOfClass:NSPopUpButton.class]) {
				NSPopUpButton *popup = (NSPopUpButton *)subview;
				if(popup.numberOfItems == statusImages.count) {
					NSMenuItem *item = popup.itemArray.firstObject;
					if(!item.image && [item.title isEqualToString:@"Not called"]) {
						int i = 0;
						for(NSMenuItem *item in popup.itemArray) {
							if(i < statusImages.count) {
								item.image = statusImages[i];
							}
							i++;
						}
						/// No more than 1 popup button should require images, at a given time.
						return;
					}
				}
			}
		}
	}
}


#pragma mark - recording and restoring selection

- (NSString *)userDefaultKeyForSelectedItemIDs {
	return @"selectedGenotypes";
}


-(void)recordSelectedItems {
	SampleFolder *selectedFolder = FolderListController.sharedController.selectedFolder;
	if(!selectedFolder) {
		return;
	}
	NSString *folderID = selectedFolder.objectID.URIRepresentation.absoluteString;
	if(folderID) {
		[self recordSelectedItemsAtKey:folderID maxRecorded:100];
	}
}


-(void)restoreSelectedItems {
	SampleFolder *selectedFolder = FolderListController.sharedController.selectedFolder;
	if(!selectedFolder) {
		return;
	}
	NSString *folderID = selectedFolder.objectID.URIRepresentation.absoluteString;
	if(folderID) {
		[self restoreSelectedItemsAtKey:folderID];
	}
}

#pragma mark - other

- (void)dealloc {
	@try {
		[NSNotificationCenter.defaultCenter removeObserver:self];
	} @catch (NSException *exception) {
	}
}

@end
