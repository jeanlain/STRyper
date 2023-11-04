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
#import "Genotype.h"
#import "Mmarker.h"
#import "Panel.h"
#import "SampleTableController.h"
#import "FolderListController.h"
#import "IndexImageView.h"
#import "NSPredicate+PredicateAdditions.h"
#import "AggregatePredicateEditorRowTemplate.h"
#import "Allele.h"

@implementation GenotypeTableController {
	NSDictionary *columnDescription;
	BOOL shouldRefreshTable;				/// To know if we need to refresh of the genotype table.
	NSArray<NSImage *> *statusImages;		/// The images that represent the different genotype statuses.
	__weak IBOutlet NSButton *filterButton;	/// The button to apply a filter to the table
	NSPopover *filterPopover;				/// The popover allowing to define the filter
	NSMutableDictionary *filterForFolder;	/// To save filters to the user defaults, for each folder that has a filter
}

/// pointers giving context to a KVO notification
static void * const samplesChangedContext = (void*)&samplesChangedContext;
static void * const genotypeFilterChangedContext = (void*)&genotypeFilterChangedContext;


+ (instancetype)sharedController {
	static GenotypeTableController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = [[self alloc] init];
	});
	return controller;
}

- (instancetype)init {
	return [super initWithNibName:@"GenotypeTab" bundle:nil];
}



- (void)viewDidLoad {
	[super viewDidLoad];
	/// the order of the image in the array corresponds to genotypeStatus property of genotypes (an integer)
	statusImages = @[[NSImage imageNamed:@"circle"],
					 [NSImage imageNamed:@"zero"],
					 [NSImage imageNamed:@"filled circle"],
					 [NSImage imageNamed:NSImageNameCaution],
					 [NSImage imageNamed:NSImageNameStatusPartiallyAvailable],
					 [NSImage imageNamed:@"edited round"]];
	
	/// Here we set up observations to know when to update the table. We once used to bind the genotypes NSArrayController contents to the @unionOfSets.genotypes keypaths of the samples shown in the table
	/// however, this caused severe performance issues when a panel was applied to thousands of samples, as this creates genotypes for every sample successively, which refreshes the table at each step
	/// so we update the table "manually". The genotypes NSArrayController still has its arranged objects, sort descriptors and selection indexes bounds to the table's content (as it is convenient for sorting)
	/// but the content of the controller itself is what we set manually at appropriate times.
	/// We do it when the samples shown in the sample table change, as we must list heir genotypes
	/// We do also do it when a panel has its marker changed, as this may create or delete genotypes
	/// and when a marker has its samples changed (when it is applied to samples, or "unapplied" when it is replaced by another panel)
	
	if(SampleTableController.sharedController.samples) {
		/// we get notified when the samples shown changes
		[SampleTableController.sharedController.samples addObserver:self
														 forKeyPath:NSStringFromSelector(@selector(content))
															options:NSKeyValueObservingOptionNew
															context:samplesChangedContext];
		/// We don't observe `arrangedObjects` as we don't need to react to changes in the sort order of the samples.
		
		[SampleTableController.sharedController.samples addObserver:self
														 forKeyPath:NSStringFromSelector(@selector(filterPredicate))
															options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
															context:samplesChangedContext];
		
		[FolderListController.sharedController addObserver:self
														 forKeyPath:NSStringFromSelector(@selector(selectedFolder))
															options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
															context:samplesChangedContext];
		[self.genotypes addObserver:self
						 forKeyPath:NSStringFromSelector(@selector(filterPredicate))
							options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
							context:genotypeFilterChangedContext];
	}
	/// we get notified when a panel has its samples or marker changed
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(panelMarkersDidChange:) name:PanelMarkersDidChangeNotification object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(panelSamplesDidChange:) name:PanelSamplesDidChangeNotification object:nil];
	
	/// We also observe when the context commits changes, as this is the right time to update the table.
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
			@"genotypeSampleColumn":	@{KeyPathToBind: @"sample.sampleName",ColumnTitle: @"Sample", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"genotypeStatusColumn":	@{KeyPathToBind: @"statusText", ImageIndexBinding: @"status" ,ColumnTitle: @"Status", CellViewID: @"imageCellView", IsColumnVisibleByDefault: @YES},
			@"genotypePanelColumn":		@{KeyPathToBind: @"sample.panel.name",ColumnTitle: @"Panel", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"genotypeMarkerColumn":	@{KeyPathToBind: @"marker.name",ColumnTitle: @"Marker", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
		/*	@"genotypeScan1Column":		@{KeyPathToBind: @"allele1.scan",ColumnTitle: @"Scan1", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},
			@"genotypeScan2Column":		@{KeyPathToBind: @"allele2.scan",ColumnTitle: @"Scan2", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @NO},*/
			@"genotypeSize1Column":		@{KeyPathToBind: @"allele1.visibleSize",ColumnTitle: @"Size1", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"genotypeSize2Column":		@{KeyPathToBind: @"allele2.visibleSize",ColumnTitle: @"Size2", CellViewID: @"numberFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"genotypeAllele1Column":	@{KeyPathToBind: @"allele1.name",ColumnTitle: @"Allele1", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES},
			@"genotypeAllele2Column":	@{KeyPathToBind: @"allele2.name",ColumnTitle: @"Allele2", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES},
			@"genotypeOffsetColumn":	@{KeyPathToBind: @"offsetString",ColumnTitle: @"Offset", CellViewID: @"textFieldCellView", IsTextFieldEditable: @NO, IsColumnVisibleByDefault: @YES},
			@"genotypeNotesColumn":	@{KeyPathToBind: @"notes",ColumnTitle: @"Notes", CellViewID: @"textFieldCellView", IsTextFieldEditable: @YES, IsColumnVisibleByDefault: @YES}
		};
	}
	return columnDescription;
}

- (NSArray<NSString *> *)orderedColumnIDs {
	/// a column with id @"genotypeStatusColumn" (genotype status) is already set in IB.
	/// This is because the table shifts to cell-based if it doesn't have a column in Xcode 14. So it must have a column.
	/// We don't add it to the identifiers
	return @[@"genotypeSampleColumn", @"genotypePanelColumn",@"genotypeMarkerColumn",/* @"genotypeScan1Column", @"genotypeScan2Column", */
			 @"genotypeSize1Column",@"genotypeSize2Column", @"genotypeAllele1Column", @"genotypeAllele2Column", @"genotypeOffsetColumn", @"genotypeNotesColumn"];
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
			if(gen.alleles.count < 2) {
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

/// The table must be update when:
/// - the samples shown in the selected folder changes, as we show their genotypes
/// - markers change, as we create a genotype for each sample analyzed at a marker (and we delete genotypes if the marker is removed)
/// - when a panel is applied to samples

-(void)panelMarkersDidChange:(NSNotification *)notification {
	Panel *panel = notification.object;
	if([panel isKindOfClass:Panel.class] && panel.managedObjectContext == self.genotypes.managedObjectContext) {
		if(panel.samples.count > 0) {
			/// if the panel is not applied to samples, there is no genotype create or deleted
			/// we could further check the some samples are among those shown in the sample table, but I'm not sure this would save much time
			shouldRefreshTable = YES;
		}
	}
}


-(void)panelSamplesDidChange:(NSNotification *)notification {
	Panel *panel = notification.object;
	if([panel isKindOfClass:Panel.class] && panel.managedObjectContext == self.genotypes.managedObjectContext) {
		if(panel.markers.count > 0) {
			/// if a panel has no marker, changing its samples cannot create new genotypes
			shouldRefreshTable = YES;
		}
	}
}


-(void)contextDidChange:(NSNotification *)notification {
	if(shouldRefreshTable) {
		[self refreshTable];
		shouldRefreshTable = NO;
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == samplesChangedContext) {
		if([keyPath isEqualToString:NSStringFromSelector(@selector(selectedFolder))]) {
			/// If a folder is selected, we apply its filter
			[self filterGenotypesOfSelectedFolder];
		}
		[self refreshTable];
		
	} else if(context == genotypeFilterChangedContext) {
		/// We change the button image to reflect the presence of a filter
		filterButton.image = self.genotypes.filterPredicate? [NSImage imageNamed:@"filterButton On"]: [NSImage imageNamed:@"filterButton"];
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


-(void)refreshTable {
	self.genotypes.content = [SampleTableController.sharedController.samples.arrangedObjects valueForKeyPath:@"@unionOfSets.genotypes"];
}


#pragma mark - user actions on genotypes

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(resetOffsets:)) {
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


- (IBAction)callAlleles:(id)sender {
	/// we don't create a managed object context to call alleles as allele call is very quick (less than 1s for 10000 genotypes)
	/// and is actually slower when we use a child context

	BOOL doAll = self.tableView.clickedRow >= 0;
	/// if the message was sent by the tableView's menu, we call the alleles of all target genotypes
	/// else, we will call alleles only for genotypes that have not been called or edited
	
	NSArray *genotypes = doAll? [self targetItemsOfSender:sender] : self.genotypes.arrangedObjects;

	for (Genotype *genotype in genotypes) {
		if(doAll || (genotype.status != genotypeStatusCalled && genotype.status != genotypeStatusManual)) {
			[genotype callAlleles];
		}
	}
	
	[self.undoManager setActionName:@"Call Alleles"];
	[(AppDelegate *)NSApp.delegate saveAction:self];

}


- (IBAction)showSamples:(id)sender {
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


- (void)resetOffsets:(id)sender {
	NSArray *genotypes = [self targetItemsOfSender:sender];
	for(Genotype *genotype in genotypes) {
		genotype.offsetData = nil;
	}
	[self.undoManager setActionName:@"Reset Genotype Offset(s)"];
	[(AppDelegate *)NSApp.delegate saveAction:self];
}


- (IBAction)exportGenotypes:(id)sender {
	NSArray *gen = self.genotypes.arrangedObjects;		/// if this is sent from the export button, all genotypes are exported
	if(self.tableView.clickedRow >= 0) {				/// if sent from the genotype table menu (meaning that a row has been clicked), only selected/clicked genotypes are exported
		gen = [self targetItemsOfSender:sender];
	}
	if (gen.count == 0) {
		return;
	}
	
	NSSavePanel* panel = NSSavePanel.savePanel;
	NSButton* button = [NSButton checkboxWithTitle:@"Add Sample-related Columns" target:nil action:nil];	/// we allow the user to add sample-related information (from the sample table)
	panel.accessoryView = button;
	button.state = [NSUserDefaults.standardUserDefaults boolForKey:AddSampleInfo];
	[button setFrameSize:NSMakeSize(button.frame.size.width, 40)];
	
	panel.nameFieldStringValue = @"genotypes.txt";
	panel.allowedFileTypes = @[@"public.plain-text"];
	[panel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSURL* theFile = panel.URL;
			[NSUserDefaults.standardUserDefaults setBool:button.state forKey:AddSampleInfo];
			NSString *exportString = [self stringFromGenotypes:gen withSampleInfo:button.state];
			NSError *error = nil;
			[exportString writeToURL:theFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
			if(error) {
				[NSApp presentError:error];
			}
		}
	}];
	
}


/// creates a string from an array of genotypes based on the table columns
- (NSString *) stringFromGenotypes:(NSArray *)gen withSampleInfo: (BOOL)addSampleInfo {
	
	NSMutableString *exportString = NSMutableString.new;
	NSMutableArray *exportStrings = NSMutableArray.new;

	/// we make a header with column names
	BOOL nameColumnShown = NO;
	for(NSTableColumn *column in self.visibleColumns) {
		if([column.title isEqualToString:@"Sample"]) {
			nameColumnShown = YES;
		}
		[exportStrings addObject: column.headerCell.stringValue];
	}
	
	if(addSampleInfo) {
		for(NSTableColumn *column in SampleTableController.sharedController.visibleColumns) {
			if(!([column.identifier isEqualToString:@"sampleNameColumn"] && nameColumnShown)) {
				[exportStrings addObject: column.headerCell.stringValue];
			}
		}
	}
	
	NSString *row = [exportStrings componentsJoinedByString:@"\t"];
	[exportString appendFormat:@"%@\n", row];
	
	for (Genotype *genotype in gen) {
		[exportStrings removeAllObjects];
		/// we export data as shown in the table, hence based on the displayed columns and their order
		[exportStrings addObject: [self stringForObject:genotype]];
		if(addSampleInfo) {
			Chromatogram *sample = genotype.sample;
			SampleTableController *sampleTableController = SampleTableController.sharedController;
			for (NSTableColumn *column in  sampleTableController.visibleColumns) {
				if(!([column.identifier isEqualToString:@"sampleNameColumn"] && nameColumnShown)) { /// the sample name column is already part of the genotype table
					[exportStrings addObject: [sampleTableController stringCorrespondingToColumn:column forObject:sample]];
				}
			}
		}
		row = [exportStrings componentsJoinedByString:@"\t"];
		[exportString appendFormat:@"%@\n", row];
	}
	return exportString;
}


#pragma mark - genotype filtering

NSString* const GenotypeFiltersKey = @"genotypeFiltersKey";


/// Configures and shows the popover allowing to filter the table
/// - Parameter sender: The object that sent this message.
- (IBAction)showFilterPopover:(id)sender {
	
	if(!filterPopover) {
		
		filterPopover = NSPopover.new;
		NSViewController *controller = [[NSViewController alloc] initWithNibName:@"FilterPopover" bundle:nil];
		if(controller) {
			filterPopover.contentViewController = controller;
		} else {
			NSLog(@"Failed to load filter popover!");
			return;
		}
		
		filterPopover.animates = YES;
		filterPopover.behavior = NSPopoverBehaviorTransient;
		NSView *contentView = controller.view;
		NSButton *cancelButton = [contentView viewWithTag:4];
		cancelButton.action = @selector(close);
		cancelButton.target = filterPopover;
		
		NSButton *clearFilterButton = [contentView viewWithTag:5];
		clearFilterButton.action = @selector(clearFilter:);
		clearFilterButton.target = self;
		[clearFilterButton bind:NSEnabledBinding toObject:self.genotypes withKeyPath:@"filterPredicate" options:@{NSValueTransformerNameBindingOption: NSIsNotNilTransformerName}];
		
		NSButton *applyFilterButton = [contentView viewWithTag:6];
		applyFilterButton.action = @selector(applyFilter:);
		applyFilterButton.target = self;
	
		NSPredicateEditor *predicateEditor = [contentView viewWithTag:2];
		
		/// we remove the background of the editor, which is defined by a visual effect view in macOS 14.
		NSView *view = predicateEditor.subviews.firstObject;
		view = view.subviews.firstObject;
		view = view.subviews.firstObject;
		if([view isKindOfClass:NSVisualEffectView.class]) {
			view.hidden = YES;
		}
		
		/// we prepare the keyPaths (attributes) that the predicate editor will allow filtering.
		NSArray *keyPaths = @[@"marker.name", @"marker.panel.name", @"notes"];
		
		NSArray *rowTemplates = [NSPredicateEditorRowTemplate templatesWithAttributeKeyPaths:keyPaths inEntityDescription:Genotype.entity];
		
		/// We add row templates to filter according to allele properties, which are to-many relationships
		NSPredicateEditorRowTemplate *markerTemplate = rowTemplates.firstObject;
		
		NSPredicateEditorRowTemplate *alleleNameTemplate = [[AggregatePredicateEditorRowTemplate alloc]
															initWithLeftExpressions:@[[NSExpression expressionForKeyPath:@"alleles.name"]]
															rightExpressionAttributeType:NSStringAttributeType
															modifier:NSAnyPredicateModifier
															operators:markerTemplate.operators
															options:0];
		
		
		NSPredicateEditorRowTemplate *alleleSizeTemplate = [[AggregatePredicateEditorRowTemplate alloc]
															initWithLeftExpressions:@[[NSExpression expressionForKeyPath:@"alleles.size"]]
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
		
				
		NSArray *finalTemplates = [@[alleleNameTemplate, alleleSizeTemplate] arrayByAddingObjectsFromArray:rowTemplates];
		 finalTemplates = [finalTemplates arrayByAddingObject:interceptTemplate];
		
		NSArray *compoundTypes = @[@(NSNotPredicateType), @(NSAndPredicateType),  @(NSOrPredicateType)];
		NSPredicateEditorRowTemplate *compound = [[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:compoundTypes];
				
		/// The predicate editor has a compound predicate row template created in IB, we keep it
		predicateEditor.rowTemplates = [@[compound] arrayByAddingObjectsFromArray:finalTemplates];
		predicateEditor.canRemoveAllRows = NO;
		
		/// We create a formatting dictionary to translate attribute names into menu item titles. We don't translate other fields (operators)
		keyPaths = [@[@"alleles.name", @"alleles.size"] arrayByAddingObjectsFromArray:keyPaths];
		keyPaths = [keyPaths arrayByAddingObject:NSStringFromSelector(@selector(offsetIntercept))];

		/// The titles for the menu items of the editor left popup buttons
		NSArray *titles = @[@"Allele Name", @"Allele Size", @"Marker Name", @"Panel Name", @"Notes", @"Offset"];

		NSArray *keys = NSArray.new;		/// the future keys of the dictionary
		for(NSString *keyPath in keyPaths) {
			NSString *key = [NSString stringWithFormat: @"%@%@%@",  @"%[", keyPath, @"]@ %@ %@"];		/// see https://funwithobjc.tumblr.com/post/1482915398/localizing-nspredicateeditor
			if([keyPaths indexOfObject:keyPath] < 2) {
				key = [key stringByAppendingString: @" %@"];
			}
			keys = [keys arrayByAddingObject:key];
		}
		
		NSArray *values = NSArray.new;	/// the future values
		for(NSString *title in titles) {
			NSString *value = [NSString stringWithFormat: @"%@%@%@",  @"%1$[", title, @"]@ %2$@ %3$@"];
			if([titles indexOfObject:title] < 2) {
				value = [value stringByAppendingString: @" %4$@"];
			}
			values = [values arrayByAddingObject:value];
		}
		
		predicateEditor.formattingDictionary = [NSDictionary dictionaryWithObjects:values forKeys:keys];
	}
	
	/// We set the predicate to show in the editor
	NSPredicate *filterPredicate = self.genotypes.filterPredicate;
	if(!filterPredicate) {
		/// The default predicate is based on the allele name
		filterPredicate = [NSPredicate predicateWithFormat: @"ANY alleles.name ==[c] ''"];
	}
	
	if(filterPredicate.class != NSCompoundPredicate.class) {
		/// we make the search predicate a compound predicate to make sure it shows the "all/any/none" option.
		filterPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[filterPredicate]];
	}
	
	NSView *contentView = filterPopover.contentViewController.view;
	
	NSButton *caseSensitiveButton = [contentView viewWithTag:3];
	caseSensitiveButton.state = filterPredicate.isCaseInsensitive? NSControlStateValueOn : NSControlStateValueOff;
	
	NSPredicateEditor *editor = [contentView viewWithTag:2];
	editor.objectValue = filterPredicate;
	
	NSTextField *errorTextField = [contentView viewWithTag:7];
	errorTextField.hidden = YES;
	
	[filterPopover showRelativeToRect:filterButton.bounds ofView:filterButton preferredEdge:NSMinYEdge];
}

/// Removes the current filter of the table.
-(void)clearFilter:(id)sender {
	[filterPopover close];
	self.genotypes.filterPredicate = nil;
	[self recordFilterPredicate];
}

/// Applies the filter predicate defined by the `filterPopover` to the table.
-(void)applyFilter:(id)sender {
	NSView *contentView = filterPopover.contentViewController.view;
	NSPredicateEditor *editor = [contentView viewWithTag:2];
	NSPredicate *filterPredicate = editor.predicate;
	
	if(filterPredicate.hasEmptyTerms) {
		NSTextField *errorTextField = [contentView viewWithTag:7];
		errorTextField.hidden = NO;
		return;
	}
	
	NSButton *caseSensitiveButton = [contentView viewWithTag:3];
	
	if(caseSensitiveButton.state == NSControlStateValueOn) {
		filterPredicate = [filterPredicate caseInsensitivePredicate];
	}
	
	if([filterPredicate isEqualTo:self.genotypes.filterPredicate]) {
		[self.genotypes rearrangeObjects];
	} else {
		self.genotypes.filterPredicate = filterPredicate;
		[self recordFilterPredicate];
	}
	
	[filterPopover close];
}


/// Associates the filter predicate to the selected folder in the user defaults
-(void)recordFilterPredicate {
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
	
	if(!filterForFolder) {
		filterForFolder = [NSUserDefaults.standardUserDefaults dictionaryForKey:GenotypeFiltersKey].mutableCopy;
		if(!filterForFolder) {
			filterForFolder = NSMutableDictionary.new;
		}
	}
	
	NSData *filterPredicateData;
	NSPredicate *filterPredicate = self.genotypes.filterPredicate;
	if(filterPredicate) {
		filterPredicateData = [NSKeyedArchiver archivedDataWithRootObject:filterPredicate
								requiringSecureCoding:YES
												error:nil];

	}
	
	if(filterPredicateData) {
		filterForFolder[key] = filterPredicateData;
	} else {
		[filterForFolder removeObjectForKey:key];
	}
	
	[NSUserDefaults.standardUserDefaults setObject:filterForFolder forKey:GenotypeFiltersKey];
}

/// Applies the filter associated to the selected folder to the table, retrieving it from the user defaults
-(void) filterGenotypesOfSelectedFolder {
	if(!filterForFolder) {
		filterForFolder = [NSUserDefaults.standardUserDefaults dictionaryForKey:GenotypeFiltersKey].mutableCopy;
		if(!filterForFolder) {
			self.genotypes.filterPredicate = nil;
			return;
		}
	}
	
	NSString *key = FolderListController.sharedController.selectedFolder.objectID.URIRepresentation.absoluteString;
	if(key) {
		NSData *predicateData = filterForFolder[key];
		if([predicateData isKindOfClass:NSData.class]) {
			NSPredicate *filterPredicate = [NSKeyedUnarchiver unarchivedObjectOfClass:NSPredicate.class fromData:predicateData error:nil];
			[filterPredicate allowEvaluation];
			self.genotypes.filterPredicate = filterPredicate;
			return;
		}
	}
	self.genotypes.filterPredicate = nil;
}


#pragma mark - other

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[SampleTableController.sharedController.samples removeObserver:self forKeyPath:NSStringFromSelector(@selector(content))];
	[SampleTableController.sharedController.samples removeObserver:self forKeyPath:NSStringFromSelector(@selector(filterPredicate))];
	[self.genotypes removeObserver:self forKeyPath:NSStringFromSelector(@selector(filterPredicate))];
}

@end
