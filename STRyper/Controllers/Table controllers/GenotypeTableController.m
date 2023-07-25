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
#import "IndexImageView.h"

@implementation GenotypeTableController {
	NSDictionary *columnDescription;
	BOOL shouldRefreshTable;				/// To know if we need to refresh of the genotype table.
	NSArray<NSImage *> *statusImages;		/// The images that represent the different genotype statuses.

}

/// a pointer giving context to a KVO notification
static void * const samplesChangedContext = (void*)&samplesChangedContext;


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
		[SampleTableController.sharedController.samples addObserver:self forKeyPath:@"content" options:NSKeyValueObservingOptionNew context:samplesChangedContext];
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
			[self refreshTable];
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


-(void)refreshTable {
	self.genotypes.content = [SampleTableController.sharedController.samples.content valueForKeyPath:@"@unionOfSets.genotypes"];
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
	
	/// we make a header with column names
	for(NSTableColumn *column in self.tableView.tableColumns) {
		[exportString appendString: column.headerCell.stringValue];
		[exportString appendString: @"\t"];
	}
	
	if(addSampleInfo) {
		for(NSTableColumn *column in SampleTableController.sharedController.tableView.tableColumns) {
			if(![column.identifier isEqualToString:@"sampleNameColumn"] && !column.hidden) {
				[exportString appendString: column.headerCell.stringValue];
				[exportString appendString: @"\t"];
			}
		}
	}
	
	[exportString deleteCharactersInRange:NSMakeRange(exportString.length-1, 1)];	/// we remove the last superfluous tab
	[exportString appendString: @"\n"];
	
	for (Genotype *genotype in gen) {
		/// we export data as shown in the table, hence based on the displayed columns and their order
		[exportString appendString: [self stringForObject:genotype]];
		[exportString appendString: @"\t"];
		if(addSampleInfo) {
			Chromatogram *sample = genotype.sample;
			SampleTableController *sampleTableController = SampleTableController.sharedController;
			for (NSTableColumn *column in  sampleTableController.tableView.tableColumns) {
				if(![column.identifier isEqualToString:@"sampleNameColumn"] && !column.hidden) { /// the sample name column is already part of the genotype table
					[exportString appendString: [sampleTableController stringCorrespondingToColumn:column forObject:sample]];
					[exportString appendString:@"\t"];
				}
			}
		}
		
		[exportString deleteCharactersInRange:NSMakeRange(exportString.length-1, 1)];	// we remove the last superfluous tab
		[exportString appendString: @"\n"];
	}
	return exportString;
}

#pragma mark - other

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[SampleTableController.sharedController.samples removeObserver:self forKeyPath:@"content"];
}

@end
