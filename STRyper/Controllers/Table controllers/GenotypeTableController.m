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


@interface GenotypeTableController ()

/// A variable bound to the genotypes shown in the genotype table.
@property (nonatomic) NSArray *genotypeContent;

@property (nonatomic) NSDictionary<NSString *, NSString *> *actionNamesForColumnIDs;

@end


@implementation GenotypeTableController {
	NSDictionary *columnDescription;
	BOOL selectedFolderHasChanged;
	BOOL shouldRefreshTable;				/// To know if we need to refresh of the genotype table.
	NSArray<NSImage *> *statusImages;		/// The images that represent the different genotype statuses.
	NSMutableDictionary *filterDictionary;	/// To save filters to the user defaults, for each folder that has a filter
}

/// pointers giving context to a KVO notification
static void * const selectedFolderChangedContext = (void*)&selectedFolderChangedContext;
static void * const sampleFilterChangedContext = (void*)&sampleFilterChangedContext;


+ (instancetype)sharedController {
	static GenotypeTableController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = [[self alloc] init];
	});
	return controller;
}


- (NSNibName)nibName {
	return @"GenotypeTab";
}


- (void)viewDidLoad {
	[super viewDidLoad];
	/// the order of the image in the array corresponds to genotypeStatus property of genotypes (an integer)
	statusImages = @[[NSImage imageNamed:@"circle"],
					 [NSImage imageNamed:@"zero"],
					 [NSImage imageNamed:@"filled circle"],
					 [NSImage imageNamed:@"danger"],
					 [NSImage imageNamed:NSImageNameStatusPartiallyAvailable],
					 [NSImage imageNamed:@"edited round"]];
	
	if(SampleTableController.sharedController.samples) {
		
		/// We once used to bind the genotypes NSArrayController contents to the @unionOfSets.genotypes keypaths of the samples shown in the table
		/// however, this caused severe performance issues when a panel was applied to thousands of samples, as this creates genotypes for every sample successively, which refreshes the genotype table at each step.
		/// So we bind to our dedicated property, and then update the genotype table "manually". The genotypes NSArrayController still has its arranged objects, sort descriptors and selection indexes bounds to the table's content (as it is convenient for sorting)
		/// but the content of the controller itself is what we set at appropriate times.
		[self bind:NSStringFromSelector(@selector(genotypeContent))
		  toObject:SampleTableController.sharedController.samples
	   withKeyPath:@"content.@unionOfSets.genotypes" options:nil];
		/// We dont bind to the samples `arrangedObjects` key because we don't need to update the genotype table when the sorting of samples change, for instance.
		
		/// Since the samples `content` is not changed when samples are filtered, we observe the filter predicate use to filter samples.
		[SampleTableController.sharedController.samples addObserver:self
														 forKeyPath:NSStringFromSelector(@selector(filterPredicate))
															options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
															context:sampleFilterChangedContext];
		
		/// We need to know when the selected folder change, to apply the filter on genotypes (which is specific to a folder).
		[FolderListController.sharedController addObserver:self
												forKeyPath:NSStringFromSelector(@selector(selectedFolder))
												   options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
												   context:selectedFolderChangedContext];
		
	}
	/// We observe when the context commits changes, as it is the right time to update the table.
	/// Updating just after each notification would waste resources and lead to errors (especially during undo/redo)
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contextDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:self.genotypes.managedObjectContext];
	
	[self refreshTable];
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
			@"genotypeSampleColumn":	@{KeyPathToBind: @"sample.sampleName",ColumnTitle: @"Sample", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES},
			@"genotypeStatusColumn":	@{KeyPathToBind: @"statusText", ImageIndexBinding: @"status" ,ColumnTitle: @"Status", CellViewID: @"imageCellView", IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			@"genotypePanelColumn":		@{KeyPathToBind: @"sample.panel.name",ColumnTitle: @"Panel", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES},
			@"genotypeMarkerColumn":	@{KeyPathToBind: @"marker.name",ColumnTitle: @"Marker", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES},
			/*	@"genotypeScan1Column":		@{KeyPathToBind: @"allele1.scan",ColumnTitle: @"Scan1", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			 @"genotypeScan2Column":		@{KeyPathToBind: @"allele2.scan",ColumnTitle: @"Scan2", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},*/
			@"genotypeSize1Column":		@{KeyPathToBind: @"allele1.visibleSize",ColumnTitle: @"Size1", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			@"genotypeSize2Column":		@{KeyPathToBind: @"allele2.visibleSize",ColumnTitle: @"Size2", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			@"genotypeAllele1Column":	@{KeyPathToBind: @"allele1.name",ColumnTitle: @"Allele1", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES},
			@"genotypeAllele2Column":	@{KeyPathToBind: @"allele2.name",ColumnTitle: @"Allele2", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES},
			@"genotypeOffsetColumn":	@{KeyPathToBind: @"offsetString",ColumnTitle: @"Offset", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @NO},
			@"additionalFragmentsColumn":	@{KeyPathToBind: @"additionalFragmentString",ColumnTitle: @"Additional Peaks", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO, IsColumnSortingCaseInsensitive: @NO},
			@"genotypeNotesColumn":	@{KeyPathToBind: @"notes",ColumnTitle: @"Notes", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES, IsColumnSortingCaseInsensitive: @YES}
		};
	}
	return columnDescription;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	/// a column with id @"genotypeStatusColumn" (genotype status) is already set in IB.
	/// This is because the table shifts to cell-based if it doesn't have a column in Xcode 14. So it must have a column.
	/// We don't add it to the identifiers
	return @[@"genotypeSampleColumn", @"genotypePanelColumn",@"genotypeMarkerColumn",/* @"genotypeScan1Column", @"genotypeScan2Column", */
			 @"genotypeSize1Column",@"genotypeSize2Column", @"genotypeAllele1Column", @"genotypeAllele2Column", @"genotypeOffsetColumn", @"additionalFragmentsColumn", @"genotypeNotesColumn"];
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
	
	if([ID isEqualToString:@"genotypeAllele2Column"] || [ID isEqualToString:@"genotypeSize2Column"]) {
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
		if([view.imageView respondsToSelector:@selector(imageArray)]) {
			((IndexImageView *)view.imageView).imageArray = statusImages;
		}
	}
	
	return view;
	
}


#pragma mark - contextual menu management


- (nullable NSString *)removeActionTitleForItems:(NSArray *)items {
	return nil;  /// one cannot remove a genotype. It is removed only when a marker is no longer applied to a sample
}


#pragma mark - keeping the genotype table up-to-date



- (void)setGenotypeContent:(NSArray *)genotypeContent {
	/// We don't set any iVar because we retrieve the genotype to show during refreshTable.
	if(selectedFolderHasChanged) {
		/// if this was called after a change in selected folder, we refresh the genotype table immediately.
		[self refreshTable];
		[self restoreSelectedItems];
	} else {
		/// If not, the method must have been called due to a change in the folder content on in the markers applied to samples that are shown.
		/// In this case the managed object context has changes, so defer the update until all changed are processed.
		shouldRefreshTable = YES;
	}
}


-(void)contextDidChange:(NSNotification *)notification {
	if(shouldRefreshTable) {
		[self refreshTable];
		shouldRefreshTable = NO;
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == sampleFilterChangedContext) {
		[self refreshTable];
	} else if (context == selectedFolderChangedContext) {
		/// We don't refresh the table as the content of samples NSArrayController is not updated yet.
		selectedFolderHasChanged = YES;
		[self filterGenotypesOfSelectedFolder];
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


-(void)refreshTable {
	/// The genotypes to show are those of the sample's arrangedObject (not content) because the samples may be filtered.
	/// We  check if the content to show has changed, to avoid unnecessary updates.
	selectedFolderHasChanged = NO;
	NSArray *genotypes = [SampleTableController.sharedController.samples.arrangedObjects valueForKeyPath:@"@unionOfSets.genotypes"];
	NSArray *content = self.genotypes.content;
	BOOL refresh = NO;
	if(content.count != genotypes.count) {
		refresh = YES;
	} else {
		for(id genotype in genotypes) {
			if([content indexOfObjectIdenticalTo:genotype] == NSNotFound) {
				refresh = YES;
				break;
			}
		}
	}
	if(refresh) {
		self.genotypes.content = genotypes;
	} 
}


#pragma mark - user actions on genotypes

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(removeOffsets:)) {
		/// we hide and disable this item if no target genotype has an offset
		NSArray *genotypes = [self targetItemsOfSender:menuItem];
		for(Genotype *genotype in genotypes) {
			MarkerOffset offset = genotype.offset;
			if(offset.intercept != 0.0 || offset.slope != 1.0) {
				menuItem.hidden = NO;
				return YES;
			}
		}
		menuItem.hidden = YES;
		return NO;
	}
	
	if(menuItem.action == @selector(pasteOffset:)) {
		NSDictionary *dic = Chromatogram.markerOffsetDictionaryFromGeneralPasteBoard;
		if(dic) {
			NSArray *URIs = dic.allKeys;
			NSArray *genotypes = [self targetItemsOfSender:menuItem];
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
	
	if(menuItem.action == @selector(removeAdditionalFragments:)) {
		/// we hide and disable this item if no target genotype has an offset
		NSArray *genotypes = [self targetItemsOfSender:menuItem];
		for(Genotype *genotype in genotypes) {
			if(genotype.additionalFragments.count > 0) {
				menuItem.hidden = NO;
				return YES;
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
	return ![self.genotypes.selectionIndexes containsIndex: row];
}


- (IBAction)binAlleles:(id)sender {
	/// if the message is sent by the tableView's menu, we call all target genotypes
	/// else, we will ignore manually edited genotypes
	BOOL doAll = [sender isKindOfClass:NSMenuItem.class] && [sender topMenu] == self.tableView.menu;
	
	NSArray *genotypes = doAll? [self targetItemsOfSender:sender] : self.genotypes.arrangedObjects;
	
	BOOL annotateSuppPeaks = [NSUserDefaults.standardUserDefaults boolForKey:AnnotateAdditionalPeaks];
	
	for (Genotype *genotype in genotypes) {
		GenotypeStatus status = genotype.status;
		if(status == genotypeStatusNotCalled || status == genotypeStatusNoPeak) {
			[genotype callAllelesAndAdditionalPeak:annotateSuppPeaks];
		} else if((doAll || status != genotypeStatusManual)) {
			/// if genotypeStatusAutomatic, the action should have no effect either (automatic binning is already done) 
			/// but we do it again as a safety measure.
			[genotype binAlleles];
		}
	}
	
	[self.undoManager setActionName:@"Bin Alleles"];
	[(AppDelegate *)NSApp.delegate saveAction:self];
}


- (IBAction)callAlleles:(id)sender {
	/// we don't create a managed object context to call alleles as allele call is very quick (less than 1s for 10000 genotypes)
	/// and is actually slower when we use a child context
	
	BOOL doAll = [sender isKindOfClass:NSMenuItem.class] && [sender topMenu] == self.tableView.menu;
	/// if the message was sent by the tableView's menu, we call the alleles of all target genotypes
	/// else, we will call alleles only for genotypes that have not been called or edited
	
	NSArray *genotypes = doAll? [self targetItemsOfSender:sender] : self.genotypes.arrangedObjects;
	BOOL annotateSuppPeaks = [NSUserDefaults.standardUserDefaults boolForKey:AnnotateAdditionalPeaks];

	for (Genotype *genotype in genotypes) {
		if(doAll || (genotype.status != genotypeStatusAutomatic && genotype.status != genotypeStatusManual)) {
			[genotype callAllelesAndAdditionalPeak:annotateSuppPeaks];
		}
	}
	
	[self.undoManager setActionName:@"Find Alleles"];
	[(AppDelegate *)NSApp.delegate saveAction:self];
	
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
	
	NSArray *genotypes = self.tableView.clickedRow >= 0? [self targetItemsOfSender:sender] : self.genotypes.arrangedObjects;
	
	for (Genotype *genotype in genotypes) {
		BOOL edited = NO;
		for (Allele *allele in genotype.additionalFragments) {
			[allele removeFromGenotypeAndDelete];
			edited = YES;
		}
		if(edited) {
			genotype.status = genotypeStatusManual;
		}
	}
	
	[self.undoManager setActionName:@"Remove Additional Peaks"];
	[(AppDelegate *)NSApp.delegate saveAction:self];
}


- (IBAction)selectSamples:(id)sender {
	MainWindowController *mainWindowController = MainWindowController.sharedController;
	mainWindowController.sourceController = SampleTableController.sharedController;		/// we activate the sample tableview
	[SampleTableController.sharedController.samples setSelectedObjects:[[self targetItemsOfSender:sender] valueForKeyPath:@"@unionOfObjects.sample"]];
	NSTableView *sampleTable = SampleTableController.sharedController.tableView;
	if(sampleTable) {
		NSInteger row = sampleTable.selectedRow;
		if(row >= 0) {
			[sampleTable scrollRowToVisible:row];
		}
	}
}


- (void)removeOffsets:(id)sender {
	NSArray *genotypes = [self targetItemsOfSender:sender];
	for(Genotype *genotype in genotypes) {
		genotype.offsetData = nil;
	}
	[self.undoManager setActionName:@"Reset Genotype Offset(s)"];
	[(AppDelegate *)NSApp.delegate saveAction:self];
}


- (IBAction)exportGenotypes:(id)sender {
	NSArray *genotypes = self.genotypes.arrangedObjects;		/// if this is sent from the export button, all genotypes are exported
	if(self.tableView.clickedRow >= 0) {				/// if sent from the genotype table menu (meaning that a row has been clicked), only selected/clicked genotypes are exported
		genotypes = [self targetItemsOfSender:sender];
	}
	if (genotypes.count == 0) {
		return;
	}
	
	NSSavePanel* panel = NSSavePanel.savePanel;
	/// we allow the user to add sample-related information (from the sample table)
	NSButton* button = [NSButton checkboxWithTitle:@"Add Sample-related Columns" target:nil action:nil];
	button.toolTip = @"Add columns from the sample table to each genotype";
	panel.accessoryView = button;
	button.state = [NSUserDefaults.standardUserDefaults boolForKey:AddSampleInfo];
	[button setFrameSize:NSMakeSize(button.frame.size.width, 40)];
	
	panel.nameFieldStringValue = [FolderListController.sharedController.selectedFolder.name stringByAppendingString: @" genotypes.txt"];
	panel.allowedFileTypes = @[@"public.plain-text"];
	
	[panel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSURL* theFile = panel.URL;
			[NSUserDefaults.standardUserDefaults setBool:button.state forKey:AddSampleInfo];
			NSString *exportString = [self stringFromGenotypes:genotypes withSampleInfo:button.state];
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
	NSArray *targetGenotypes = [self targetItemsOfSender:sender];
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
	
	[super configurePredicateEditor:predicateEditor];
	
	NSArray *keyPaths = @[@"marker.name", @"marker.panel.name", @"notes"];
	
	NSArray<NSPredicateEditorRowTemplate *> *rowTemplates = [NSPredicateEditorRowTemplate templatesWithAttributeKeyPaths:keyPaths inEntityDescription:Genotype.entity];
	
	/// To filter according to genotype status, we prepare right expressions for the predicate row template.
	NSMutableArray *expressions = [NSMutableArray arrayWithCapacity:6];
	for(NSNumber *status in @[@(genotypeStatusNotCalled),
							  @(genotypeStatusNoPeak),
							  @(genotypeStatusAutomatic),
							  @(genotypeStatusSizingChanged),
							  @(genotypeStatusMarkerChanged),
							  @(genotypeStatusManual)]) {
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
	
	NSPredicateEditorRowTemplate *interceptTemplate = [[NSPredicateEditorRowTemplate alloc]
														initWithLeftExpressions:@[[NSExpression expressionForKeyPath:NSStringFromSelector(@selector(offsetIntercept))]]
														rightExpressionAttributeType:NSFloatAttributeType
														modifier:NSDirectPredicateModifier
														operators:@[@(NSGreaterThanPredicateOperatorType), @(NSLessThanPredicateOperatorType), @(NSEqualToPredicateOperatorType), @(NSNotEqualToPredicateOperatorType)]
														options:0];
	
			
	NSArray *finalTemplates = [@[statusTemplate, alleleNameTemplate, alleleSizeTemplate] arrayByAddingObjectsFromArray:rowTemplates];
	 finalTemplates = [finalTemplates arrayByAddingObject:interceptTemplate];
	
	NSArray *compoundTypes = @[@(NSNotPredicateType), @(NSAndPredicateType),  @(NSOrPredicateType)];
	NSPredicateEditorRowTemplate *compound = [[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:compoundTypes];
			
	predicateEditor.rowTemplates = [@[compound] arrayByAddingObjectsFromArray:finalTemplates];
	predicateEditor.canRemoveAllRows = NO;
	
	/// We create a formatting dictionary to translate attribute names into menu item titles. We don't translate other fields (operators)
	keyPaths = [@[@"status", @"assignedAlleles.name", @"assignedAlleles.size"] arrayByAddingObjectsFromArray:keyPaths];
	keyPaths = [keyPaths arrayByAddingObject:NSStringFromSelector(@selector(offsetIntercept))];

	/// The titles for the menu items of the editor left popup buttons
	NSArray *titles = @[@"Status", @"Allele Name", @"Allele Size", @"Marker Name", @"Panel Name", @"Notes", @"Offset"];

	NSMutableArray *keys = NSMutableArray.new;		/// the future keys of the dictionary
	for(NSString *keyPath in keyPaths) {
		if([keyPath isEqualToString:@"status"]) {
			/// We need to translate each status number into a string.
			for (int status = genotypeStatusNotCalled; status <= genotypeStatusManual; status++) {
				NSString *key = [NSString stringWithFormat: @"%@%@%@%d%@",  @"%[", keyPath, @"]@ %@ %[", status, @"]@"];
				[keys addObject:key];
			}
		} else {
			NSString *key = [NSString stringWithFormat: @"%@%@%@",  @"%[", keyPath, @"]@ %@ %@"];		/// see https://funwithobjc.tumblr.com/post/1482915398/localizing-nspredicateeditor
			if([keyPath isEqualToString:@"assignedAlleles.name"] || [keyPath isEqualToString:@"assignedAlleles.size"]) {
				key = [key stringByAppendingString: @" %@"];
			}
			[keys addObject:key];
		}
	}
	
	NSMutableArray *values = NSMutableArray.new;	/// the future values
	for(NSString *title in titles) {
		if([title isEqualToString:@"Status"]) {
			/// The different genotype statuses.
			NSArray *menuItemTitles = @[@"Not called", @"No peak found", @"Called", @"Sizing has changed", @"Marker has changed", @"Edited manually"];
			for (NSString *menuItemTitle in menuItemTitles) {
				NSString *value = [NSString stringWithFormat: @"%@%@%@%@%@",  @"%1$[", title, @"]@ %2$@ %3$[", menuItemTitle, @"]@"];
				[values addObject:value];
			}
		} else {
			NSString *value;
			if([title isEqualToString:@"Allele Name"] || [title isEqualToString:@"Allele Size"]) {
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
	/// I haven't found a better solution. Providing an custom popup button in -templateViews of NSRuleEditorRowTemplate subclass doesn't work
	/// because the predicate editor only take the menu item titles to create its own popup button.
	/// Subclassing NSRuleEditor would certainly be the best solution, but it would require much more effort.
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

UserDefaultKey SelectedGenotypes = @"selectedGenotypes";

-(void)recordSelectedItems {
	SampleFolder *selectedFolder = FolderListController.sharedController.selectedFolder;
	if(!selectedFolder) {
		return;
	}
	NSString *folderID = selectedFolder.objectID.URIRepresentation.absoluteString;
	if(folderID) {
		[self recordSelectedItemsAtUserDefaultsKey:SelectedGenotypes subKey:folderID maxRecorded:100];
	}
}


-(void)restoreSelectedItems {
	SampleFolder *selectedFolder = FolderListController.sharedController.selectedFolder;
	if(!selectedFolder) {
		return;
	}
	NSString *folderID = selectedFolder.objectID.URIRepresentation.absoluteString;
	if(folderID) {
		[self restoreSelectedItemsWithUserDefaultsKey:SelectedGenotypes subKey:folderID];
	}
}

#pragma mark - other

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[SampleTableController.sharedController.samples removeObserver:self forKeyPath:NSStringFromSelector(@selector(content))];
	[SampleTableController.sharedController.samples removeObserver:self forKeyPath:NSStringFromSelector(@selector(filterPredicate))];
	[FolderListController.sharedController removeObserver:self forKeyPath:NSStringFromSelector(@selector(selectedFolder))];
	[self.genotypes removeObserver:self forKeyPath:NSStringFromSelector(@selector(filterPredicate))];
}

@end
